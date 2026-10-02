// Renders the whole plugin (plugin.cmajorpatch) at its default parameters, on a test signal it
// writes (bursts of a saw chord), and checks what comes out as tools/test/dsp.mjs does: no NaNs or
// infinities, nothing too loud, and some sound. An instrument would want a MIDI file instead:
// `cmaj render --midi=<file>`.
//
//   node tools/test/plugin.mjs

import { writeFileSync, mkdirSync, existsSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { spawnSync } from "node:child_process";
import { readWav, levels } from "./wav.mjs";

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

const { peak, rms, bad } = levels(readWav(outPath));
const problems = [bad > 0 && `${bad} samples aren't finite`, peak > 2 && `peak ${peak.toFixed(3)}`, rms < 1e-3 && `nearly silent (rms ${rms.toExponential(2)})`].filter(Boolean);
console.log(problems.length ? `FAIL plugin: ${problems.join(", ")}` : `ok   plugin: peak ${peak.toFixed(3)}, rms ${rms.toFixed(4)}`);
process.exit(problems.length ? 1 : 0);
