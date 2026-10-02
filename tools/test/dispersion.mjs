// Measures what the Fresnel disperser really does: for a few settings, renders its impulse response
// (dsp/FresnelDisperser.cmajor, fully wet), and compares the group delay it measures with the target
// curve the controls ask for (ui/plugin/Optics.res) and with what its telemetry (phaseResponseCurve)
// reports, checks that the magnitude stays flat (it's an allpass), and shows the phase where nothing
// is dispersed (what a crossfade with the dry signal sums against). Then it sweeps the distance under
// a pure tone and measures what the moving coefficients spill above it (clicks, zipper noise).
// Fails if the magnitude moves, the telemetry disagrees with the measurement, or the sweep spills
// more than -50 dB. Compile the view first (`npm run res`).
//
//   node tools/test/dispersion.mjs [--rate=48000]

import { writeFileSync, readFileSync, mkdirSync, existsSync } from "node:fs";
import { join, dirname, relative } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import { spawnSync } from "node:child_process";

const root = join(dirname(fileURLToPath(import.meta.url)), "..", "..");
const buildDir = join(root, "build", "test");
const cmaj = process.env.CMAJ ?? "cmaj";
const rate = Number(/--rate=(\d+)/.exec(process.argv.join(" "))?.[1] ?? 48000);
mkdirSync(buildDir, { recursive: true });

const Optics = await import(pathToFileURL(join(root, "ui", "plugin", "Optics.res.mjs")).href);
const rel = (p) => relative(buildDir, p).replace(/\\/g, "/");

// The settings measured: distance (ms), chroma, aperture
const settings = [
  { name: "idle", distance: 0, chroma: 0.35, aperture: 0.7 },
  { name: "glassy", distance: 4, chroma: 0.35, aperture: 0.7 },
  { name: "violet wide", distance: 14, chroma: 1, aperture: 1 },
  { name: "red wide", distance: 20, chroma: -1, aperture: 1 },
  { name: "green slit", distance: 20, chroma: 0, aperture: 0.3 },
  { name: "red long", distance: 80, chroma: -0.8, aperture: 0.5 },
  { name: "laser", distance: 200, chroma: -0.4, aperture: 0.12 },
];
const freqs = [50, 100, 200, 500, 1000, 2000, 5000, 10000, 15000];
const impulseAt = Math.round(0.25 * rate);
const fftSize = 1 << Math.ceil(Math.log2(0.6 * rate));

function readWav(path) {
  const b = readFileSync(path);
  let pos = 12, fmt, data;
  while (pos + 8 <= b.length) {
    const id = b.toString("ascii", pos, pos + 4), size = b.readUInt32LE(pos + 4);
    if (id === "fmt ") {
      const tag = b.readUInt16LE(pos + 8);
      fmt = { format: tag === 0xfffe ? b.readUInt16LE(pos + 32) : tag, channels: b.readUInt16LE(pos + 10), bits: b.readUInt16LE(pos + 22) };
    }
    if (id === "data") data = b.subarray(pos + 8, pos + 8 + size);
    pos += 8 + size + (size & 1);
  }
  const bytes = fmt.bits / 8, frames = Math.floor(data.length / (bytes * fmt.channels));
  const read = (o) => (fmt.format === 3 ? (bytes === 8 ? data.readDoubleLE(o) : data.readFloatLE(o)) : data.readInt16LE(o) / 32768);
  return Array.from({ length: fmt.channels }, (_, c) => Float64Array.from({ length: frames }, (_, i) => read((i * fmt.channels + c) * bytes)));
}

// in-place radix-2 FFT
function fft(re, im) {
  const n = re.length;
  for (let i = 1, j = 0; i < n; i++) {
    let bit = n >> 1;
    for (; j & bit; bit >>= 1) j ^= bit;
    j ^= bit;
    if (i < j) { [re[i], re[j]] = [re[j], re[i]]; [im[i], im[j]] = [im[j], im[i]]; }
  }
  for (let len = 2; len <= n; len <<= 1) {
    const ang = (-2 * Math.PI) / len;
    for (let i = 0; i < n; i += len)
      for (let k = 0; k < len / 2; k++) {
        const wr = Math.cos(ang * k), wi = Math.sin(ang * k);
        const a = i + k, b = a + len / 2;
        const tr = re[b] * wr - im[b] * wi, ti = re[b] * wi + im[b] * wr;
        re[b] = re[a] - tr; im[b] = im[a] - ti;
        re[a] += tr; im[a] += ti;
      }
  }
}

let failed = 0;
console.log(`at ${rate} Hz; group delay in ms, measured / target`);
for (const s of settings) {
  const base = "dispersion-" + s.name.replace(/\W+/g, "-");
  const patch = join(buildDir, base + ".cmajor");
  writeFileSync(patch, `
processor Settings
{
    output event params::Values out;
    void main()
    {
        var v = params::defaults();
        v.distance = ${s.distance.toFixed(4)}f;
        v.chroma = ${s.chroma.toFixed(4)}f;
        v.aperture = ${s.aperture.toFixed(4)}f;
        v.intensity = 0.0f;
        v.mix = 1.0f;
        out <- v;
        loop advance();
    }
}
processor Impulse
{
    output stream float<2> out;
    void main()
    {
        loop (${impulseAt}) advance();
        out <- float<2> (1.0f, 1.0f);
        loop advance();
    }
}
// the dispersed impulse, the impulse itself (where it lands is the zero), and the telemetry's
// latest curve, a point per frame
processor Pair
{
    input stream float<2> wet, dry;
    input event float[fresnel::curvePoints] curveIn;
    output stream float<4> out;
    float[fresnel::curvePoints] curve;
    event curveIn (float[fresnel::curvePoints] c)  { curve = c; }
    void main()
    {
        wrap<fresnel::curvePoints> i;
        loop { out <- float<4> (wet[0], dry[0], curve[i++], 0.0f); advance(); }
    }
}
graph Test [[ main ]]
{
    output stream float<4> out;
    node settings = Settings;
    node impulse = Impulse;
    node fx = fresnel::FresnelDisperser;
    node pair = Pair;
    connection
    {
        settings.out -> fx.paramsIn;
        impulse.out -> fx.in;
        fx.out -> pair.wet;
        impulse.out -> pair.dry;
        fx.phaseResponseCurve -> pair.curveIn;
        pair.out -> out;
    }
}
`);
  const manifest = join(buildDir, base + ".cmajorpatch");
  const sources = ["dsp/lib/Common.cmajor", "dsp/Params.cmajor", "dsp/FresnelDisperser.cmajor"].map((p) => rel(join(root, p)));
  writeFileSync(manifest, JSON.stringify({ CmajorVersion: 1, ID: "dev.test." + base, version: "1.0", name: base, source: [...sources, rel(patch)] }));
  const wav = join(buildDir, base + ".wav");
  const r = spawnSync(cmaj, ["render", manifest, `--rate=${rate}`, `--length=${2 * impulseAt + fftSize + rate}`, `--channels=4`, `--output=${wav}`], { encoding: "utf8" });
  if (r.status !== 0 || !existsSync(wav)) { console.log(`FAIL ${s.name}: didn't render\n${r.stdout}${r.stderr}`); failed++; continue; }

  const [wetOut, dryOut, curveOut] = readWav(wav);
  const points = Optics.curvePoints;
  const curveStart = Math.floor((curveOut.length - points) / points) * points;
  const curve = Array.from(curveOut.subarray(curveStart, curveStart + points));
  const zero = dryOut.findIndex((v) => Math.abs(v) > 0.5);
  const x = wetOut.subarray(zero, zero + fftSize);
  const re = Float64Array.from(x), im = new Float64Array(fftSize);
  const rn = Float64Array.from(x, (v, n) => v * n), imn = new Float64Array(fftSize);
  fft(re, im);
  fft(rn, imn);
  const bin = (hz) => Math.round((hz / rate) * fftSize);
  // group delay = Re (FFT (n h) / FFT (h)); magnitude; phase
  const at = (k) => {
    const d = re[k] * re[k] + im[k] * im[k];
    return { gd: (rn[k] * re[k] + imn[k] * im[k]) / d, db: 10 * Math.log10(d), ph: (Math.atan2(im[k], re[k]) * 180) / Math.PI };
  };
  let worstDb = 0;
  for (let k = bin(20); k < bin(Math.min(15000, 0.3 * rate)); k++) worstDb = Math.max(worstDb, Math.abs(at(k).db));

  const width = s.aperture;
  let worstCurve = 0;
  const cells = freqs.map((f) => {
    const got = (at(bin(f)).gd / rate) * 1000;
    const want = Optics.targetMs(f, s.distance, s.chroma, width);
    // what the telemetry says should be what was measured, at the curve's own point (between
    // points the curve can't follow the cascade's ripple, a few % a section's bandwidth apart)
    const i = Math.round(Optics.curveIndex(f));
    const k = (Optics.curveHz(i) / rate) * fftSize, k0 = Math.floor(k);
    const there = (at(k0).gd + (at(k0 + 1).gd - at(k0).gd) * (k - k0)) * 1000 / rate;
    worstCurve = Math.max(worstCurve, Math.abs(curve[i] - there) / (0.05 + 0.03 * Math.abs(there)));
    return `${f >= 1000 ? f / 1000 + "k" : f}:${got.toFixed(2)}/${want.toFixed(2)}`;
  });
  // where the target is zero, the phase should be too (in degrees)
  const flat = freqs.filter((f) => Optics.targetMs(f, s.distance, s.chroma, width) === 0 && f <= 10000);
  const phases = flat.map((f) => `${f >= 1000 ? f / 1000 + "k" : f}:${at(bin(f)).ph.toFixed(1)}°`);
  const ok = worstDb < 0.1 && worstCurve <= 1;
  if (!ok) failed++;
  console.log(`${ok ? "ok  " : "FAIL"} ${s.name.padEnd(12)} |H| within ${worstDb.toFixed(3)} dB, telemetry ${worstCurve <= 1 ? "matches" : "is off"} (${worstCurve.toFixed(2)} of its tolerance)`);
  console.log(`     ${cells.join("  ")}`);
  if (phases.length) console.log(`     phase where undispersed: ${phases.join("  ")}`);
}
// A 220 Hz tone while the distance sweeps 5 .. 40 ms in 6 s (red, the whole width: the tone is in
// the dispersed band). Its group delay moves, so the tone bends in pitch a little, but anything above
// 2 kHz is the coefficients' movement leaking out.
{
  const base = "dispersion-sweep";
  const patch = join(buildDir, base + ".cmajor");
  writeFileSync(patch, `
processor Settings
{
    output event params::Values out;
    void main()
    {
        var v = params::defaults();
        v.chroma = -1.0f;
        v.aperture = 1.0f;
        v.intensity = 0.0f;
        v.mix = 1.0f;
        int frame = 0;
        loop
        {
            v.distance = 5.0f + 35.0f * clamp (float (frame) / float (processor.frequency * 6.0), 0.0f, 1.0f);
            out <- v;
            loop (64) { ++frame; advance(); }
        }
    }
}
processor Tone
{
    output stream float<2> out;
    void main()
    {
        float64 phase;
        loop { phase += 220.0 / processor.frequency; out <- float<2> (float (0.5 * sin (twoPi * phase))); advance(); }
    }
}
graph Test [[ main ]]
{
    output stream float<2> out;
    node settings = Settings;
    node tone = Tone;
    node fx = fresnel::FresnelDisperser;
    connection { settings.out -> fx.paramsIn; tone.out -> fx.in; fx.out -> out; }
}
`);
  const manifest = join(buildDir, base + ".cmajorpatch");
  const sources = ["dsp/lib/Common.cmajor", "dsp/Params.cmajor", "dsp/FresnelDisperser.cmajor"].map((p) => rel(join(root, p)));
  writeFileSync(manifest, JSON.stringify({ CmajorVersion: 1, ID: "dev.test." + base, version: "1.0", name: base, source: [...sources, rel(patch)] }));
  const wav = join(buildDir, base + ".wav");
  const r = spawnSync(cmaj, ["render", manifest, `--rate=${rate}`, `--length=${7 * rate}`, `--output=${wav}`], { encoding: "utf8" });
  if (r.status !== 0 || !existsSync(wav)) {
    console.log(`FAIL sweep: didn't render
${r.stdout}${r.stderr}`);
    failed++;
  } else {
    // per 2048-point Hann frame: the energy above 2 kHz over the energy below 1 kHz, in dB
    const [x] = readWav(wav);
    const n = 2048, levels = [];
    for (let start = Math.round(0.5 * rate); start + n < x.length; start += n / 4) {
      const re = Float64Array.from({ length: n }, (_, i) => x[start + i] * (0.5 - 0.5 * Math.cos((2 * Math.PI * i) / n)));
      const im = new Float64Array(n);
      fft(re, im);
      let tone = 0, spill = 0;
      for (let k = 1; k < n / 2; k++) {
        const hz = (k * rate) / n, e = re[k] * re[k] + im[k] * im[k];
        if (hz < 1000) tone += e;
        else if (hz > 2000) spill += e;
      }
      levels.push(10 * Math.log10(spill / tone + 1e-30));
    }
    levels.sort((a, b) => a - b);
    const median = levels[levels.length >> 1], worst = levels[levels.length - 1];
    const ok = worst < -50;
    if (!ok) failed++;
    console.log(`${ok ? "ok  " : "FAIL"} sweep        spill above the tone: median ${median.toFixed(1)} dB, worst ${worst.toFixed(1)} dB`);
  }
}

process.exit(failed ? 1 : 0);
