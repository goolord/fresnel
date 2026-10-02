// What the tests read back from `cmaj render`: a WAV file's samples, and how they measure up.

import { readFileSync } from "node:fs";

// The samples of a WAV file as floats, one array per channel.
export function readWav(path) {
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

// The peak and rms of every channel together, and how many samples aren't finite.
export function levels(channels) {
  let peak = 0, sum = 0, n = 0, bad = 0;
  for (const ch of channels)
    for (const x of ch) {
      if (!Number.isFinite(x)) { bad++; continue; }
      peak = Math.max(peak, Math.abs(x));
      sum += x * x;
      n++;
    }
  return { peak, rms: Math.sqrt(sum / Math.max(1, n)), bad };
}
