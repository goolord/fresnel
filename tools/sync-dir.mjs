// Makes one folder a copy of another, touching only what differs: files whose contents changed
// are rewritten, new files are added and files missing from the source are removed. Unchanged
// files keep their timestamps, so regenerating the CLAP project (see the justfile's `generate`)
// doesn't make MSBuild/make recompile entry.cpp when the Cmajor output is the same.
//
//   node tools/sync-dir.mjs <from> <to>

import { readdirSync, readFileSync, writeFileSync, mkdirSync, rmSync, existsSync, statSync } from "node:fs";
import { join } from "node:path";

const [from, to] = process.argv.slice(2);
if (!from || !to) {
  console.error("usage: node tools/sync-dir.mjs <from> <to>");
  process.exit(1);
}

let changed = 0;

const sync = (src, dst) => {
  mkdirSync(dst, { recursive: true });
  const names = new Set(readdirSync(src));

  for (const name of readdirSync(dst)) {
    if (!names.has(name)) {
      rmSync(join(dst, name), { recursive: true, force: true });
      console.log(`removed ${join(dst, name)}`);
      changed++;
    }
  }

  for (const name of names) {
    const s = join(src, name);
    const d = join(dst, name);
    if (statSync(s).isDirectory()) {
      if (existsSync(d) && !statSync(d).isDirectory()) rmSync(d, { force: true });
      sync(s, d);
      continue;
    }
    if (existsSync(d) && statSync(d).isDirectory()) rmSync(d, { recursive: true, force: true });
    const data = readFileSync(s);
    if (existsSync(d) && readFileSync(d).equals(data)) continue;
    writeFileSync(d, data);
    console.log(`updated ${d}`);
    changed++;
  }
};

sync(from, to);
if (changed === 0) console.log(`${to} is unchanged`);
