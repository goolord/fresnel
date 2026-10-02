// Prints a field of the manifest (plugin.cmajorpatch), for the justfile: `node tools/manifest.mjs name`.
// A dotted path reaches inside: `node tools/manifest.mjs plugin.pluginCode`.

import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const manifest = JSON.parse(readFileSync(join(root, "plugin.cmajorpatch"), "utf8"));
const value = (process.argv[2] ?? "name").split(".").reduce((o, key) => o?.[key], manifest);

if (value === undefined) {
  console.error(`plugin.cmajorpatch has no ${process.argv[2]}`);
  process.exit(1);
}
process.stdout.write(typeof value === "string" ? value : JSON.stringify(value));
