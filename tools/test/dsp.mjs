// Renders every DSP test in tools/test/dsp/ and checks what comes out: no NaNs or infinities,
// nothing louder than it should be, and some sound. A test is a .cmajor file with a main graph
// or processor that has `output stream float<2> out`; it is built with the library
// (dsp/lib/*.cmajor), the test signals (tools/test/Signals.cmajor), and the plugin's own
// sources when it names them in a first-line comment `// uses: dsp/Foo.cmajor dsp/Bar.cmajor`.
// A first-line `// peak: 4` raises the loudness limit (default 4).
//
//   node tools/test/dsp.mjs [name filter]

import { readdirSync, readFileSync, writeFileSync, mkdirSync, existsSync } from "node:fs";
import { join, dirname, relative } from "node:path";
import { fileURLToPath } from "node:url";
import { spawnSync } from "node:child_process";

const root = join(dirname(fileURLToPath(import.meta.url)), "..", "..");
const testDir = join(root, "tools", "test", "dsp");
const buildDir = join(root, "build", "test");
const cmaj = process.env.CMAJ ?? "cmaj";
const filter = process.argv[2] ?? "";

mkdirSync(buildDir, { recursive: true });

const libDir = join(root, "dsp", "lib");
const lib = readdirSync(libDir).filter((f) => f.endsWith(".cmajor")).map((f) => join(libDir, f));
const rel = (p) => relative(buildDir, p).replace(/\\/g, "/");

// The samples of a WAV file as floats, one array per channel.
function readWav(path) {
  const b = readFileSync(path);
  let pos = 12, fmt, data;
  while (pos + 8 <= b.length) {
    const id = b.toString("ascii", pos, pos + 4), size = b.readUInt32LE(pos + 4);
    if (id === "fmt ") {
      // WAVE_FORMAT_EXTENSIBLE keeps the real format at the start of its subformat GUID
      const tag = b.readUInt16LE(pos + 8);
      fmt = { format: tag === 0xfffe ? b.readUInt16LE(pos + 32) : tag, channels: b.readUInt16LE(pos + 10), bits: b.readUInt16LE(pos + 22) };
    }
    if (id === "data") data = b.subarray(pos + 8, pos + 8 + size);
    pos += 8 + size + (size & 1);
  }
  if (!fmt || !data) throw new Error(`${path} isn't a WAV file`);
  const bytes = fmt.bits / 8, frames = Math.floor(data.length / (bytes * fmt.channels));
  const read = (o) =>
    fmt.format === 3 ? (bytes === 8 ? data.readDoubleLE(o) : data.readFloatLE(o))
    : bytes === 2 ? data.readInt16LE(o) / 32768
    : bytes === 3 ? data.readIntLE(o, 3) / 8388608
    : data.readInt32LE(o) / 2147483648;
  return Array.from({ length: fmt.channels }, (_, c) =>
    Float64Array.from({ length: frames }, (_, i) => read((i * fmt.channels + c) * bytes)));
}

let failed = 0, ran = 0;

for (const name of readdirSync(testDir).filter((f) => f.endsWith(".cmajor") && f.includes(filter))) {
  const file = join(testDir, name);
  const first = readFileSync(file, "utf8").split(/\r?\n/, 1)[0];
  const uses = /\/\/\s*uses:\s*(.*)/.exec(first)?.[1].split(/\s+/).filter(Boolean).map((p) => join(root, p)) ?? [];
  const limit = Number(/peak:\s*([\d.]+)/.exec(first)?.[1] ?? 4);
  const base = name.replace(/\.cmajor$/, "");
  const manifest = join(buildDir, base + ".cmajorpatch");
  const wav = join(buildDir, base + ".wav");

  writeFileSync(manifest, JSON.stringify({
    CmajorVersion: 1,
    ID: "dev.template.test." + base.toLowerCase(),
    version: "1.0",
    name: base,
    source: [...lib, ...uses, join(root, "tools", "test", "Signals.cmajor"), file].map(rel),
  }, null, 2));

  ran++;
  const r = spawnSync(cmaj, ["render", manifest, "--rate=48000", "--length=144000", `--output=${wav}`], { encoding: "utf8" });
  const output = (r.stdout ?? "") + (r.stderr ?? "");

  if (r.status !== 0 || /error/i.test(output) || !existsSync(wav)) {
    console.log(`FAIL ${base}: didn't render\n${output.trim()}`);
    failed++;
    continue;
  }

  const channels = readWav(wav);
  let peak = 0, sum = 0, n = 0, bad = 0;
  for (const ch of channels)
    for (const x of ch) {
      if (!Number.isFinite(x)) { bad++; continue; }
      peak = Math.max(peak, Math.abs(x));
      sum += x * x;
      n++;
    }
  const rms = Math.sqrt(sum / Math.max(1, n));
  const problems = [
    bad > 0 && `${bad} samples aren't finite`,
    peak > limit && `peak ${peak.toFixed(3)} is above ${limit}`,
    rms < 1e-4 && `silent (rms ${rms.toExponential(2)})`,
  ].filter(Boolean);

  if (problems.length) {
    console.log(`FAIL ${base}: ${problems.join(", ")}`);
    failed++;
  } else {
    console.log(`ok   ${base}: peak ${peak.toFixed(3)}, rms ${rms.toFixed(4)}`);
  }
}

console.log(`${ran - failed} of ${ran} passed`);
process.exit(failed ? 1 : 0);
