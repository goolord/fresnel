// Renders the whole plugin (plugin.cmajorpatch) at its default parameters, on a test signal it
// writes (bursts of a saw chord), and checks what comes out as tools/test/dsp.mjs does: no NaNs or
// infinities, nothing too loud, and some sound. An instrument would want a MIDI file instead:
// `cmaj render --midi=<file>`.
//
//   node tools/test/plugin.mjs

import { writeFileSync, mkdirSync, existsSync, readFileSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { spawnSync } from "node:child_process";

const root = join(dirname(fileURLToPath(import.meta.url)), "..", "..");
const buildDir = join(root, "build", "test");
const cmaj = process.env.CMAJ ?? "cmaj";
mkdirSync(buildDir, { recursive: true });

// A stereo 32-bit float WAV of three seconds: 0.3 s of a saw chord every second.
const rate = 48000, frames = 3 * rate;
const samples = new Float32Array(frames * 2);
for (let i = 0; i < frames; i++) {
  const t = i / rate;
  const on = t % 1 < 0.3 ? 0.4 : 0;
  const saw = [110, 138.6, 165].reduce((s, f) => s + ((t * f) % 1) - 0.5, 0) / 3;
  samples[2 * i] = samples[2 * i + 1] = on * saw;
}
const header = Buffer.alloc(44);
header.write("RIFF", 0);
header.writeUInt32LE(36 + samples.byteLength, 4);
header.write("WAVEfmt ", 8);
header.writeUInt32LE(16, 16);
header.writeUInt16LE(3, 20);
header.writeUInt16LE(2, 22);
header.writeUInt32LE(rate, 24);
header.writeUInt32LE(rate * 8, 28);
header.writeUInt16LE(8, 32);
header.writeUInt16LE(32, 34);
header.write("data", 36);
header.writeUInt32LE(samples.byteLength, 40);
const inPath = join(buildDir, "plugin-in.wav");
const outPath = join(buildDir, "plugin-out.wav");
writeFileSync(inPath, Buffer.concat([header, Buffer.from(samples.buffer)]));

const r = spawnSync(cmaj, ["render", join(root, "plugin.cmajorpatch"), `--input=${inPath}`, `--output=${outPath}`], { encoding: "utf8" });
const output = (r.stdout ?? "") + (r.stderr ?? "");
if (r.status !== 0 || /error/i.test(output) || !existsSync(outPath)) {
  console.log(`FAIL plugin: didn't render\n${output.trim()}`);
  process.exit(1);
}

// the samples that came out (float or PCM, WAVE_FORMAT_EXTENSIBLE or not)
const b = readFileSync(outPath);
let pos = 12, fmt, data;
while (pos + 8 <= b.length) {
  const id = b.toString("ascii", pos, pos + 4), size = b.readUInt32LE(pos + 4);
  if (id === "fmt ") {
    const tag = b.readUInt16LE(pos + 8);
    fmt = { format: tag === 0xfffe ? b.readUInt16LE(pos + 32) : tag, bits: b.readUInt16LE(pos + 22) };
  }
  if (id === "data") data = b.subarray(pos + 8, pos + 8 + size);
  pos += 8 + size + (size & 1);
}
const bytes = fmt.bits / 8;
let peak = 0, sum = 0, n = 0, bad = 0;
for (let o = 0; o + bytes <= data.length; o += bytes) {
  const x = fmt.format === 3 ? (bytes === 8 ? data.readDoubleLE(o) : data.readFloatLE(o)) : data.readInt16LE(o) / 32768;
  if (!Number.isFinite(x)) { bad++; continue; }
  peak = Math.max(peak, Math.abs(x));
  sum += x * x;
  n++;
}
const rms = Math.sqrt(sum / Math.max(1, n));
const problems = [bad > 0 && `${bad} samples aren't finite`, peak > 2 && `peak ${peak.toFixed(3)}`, rms < 1e-3 && `nearly silent (rms ${rms.toExponential(2)})`].filter(Boolean);
console.log(problems.length ? `FAIL plugin: ${problems.join(", ")}` : `ok   plugin: peak ${peak.toFixed(3)}, rms ${rms.toFixed(4)}`);
process.exit(problems.length ? 1 : 0);
