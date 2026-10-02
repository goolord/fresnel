// Bundles the compiled ReScript view and worker into the two self-contained ES modules the patch
// manifest loads (Cmajor can't resolve the @rescript/runtime imports itself), and gathers the
// factory presets: every file in presets/ that one of the plugin's formats reads
// (ui/plugin/Formats.res), in file-name order, into bundle/factory-presets.json, a JSON bank the
// view and the worker read (PresetStore.readFactory).
//
// run: npm run build   (compiles the ReScript sources, then bundles)

import { build } from "esbuild";
import { readFileSync, writeFileSync, readdirSync, existsSync, mkdirSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const out = join(root, "bundle");
mkdirSync(out, { recursive: true });

await build({
  entryPoints: { view: join(root, "ui", "Index.res.mjs"), worker: join(root, "worker", "PatchWorker.res.mjs") },
  outdir: out,
  bundle: true,
  format: "esm",
  platform: "browser",
  target: "es2020",
  legalComments: "none",
  logLevel: "warning",
});
console.log("ui/Index.res.mjs -> bundle/view.js, worker/PatchWorker.res.mjs -> bundle/worker.js");

// the factory presets, read with the plugin's formats
await import(pathToFileURL(join(root, "ui", "plugin", "Formats.res.mjs")).href);
const PresetFormat = await import(pathToFileURL(join(root, "ui", "presets", "PresetFormat.res.mjs")).href);
const Preset = await import(pathToFileURL(join(root, "ui", "presets", "Preset.res.mjs")).href);

const dir = join(root, "presets");
const presets = [];
for (const name of existsSync(dir) ? readdirSync(dir).sort() : []) {
  if (!PresetFormat.forFile(name)) continue;
  const result = PresetFormat.read(name, new Uint8Array(readFileSync(join(dir, name))));
  if (result.TAG === "Ok") presets.push(...result._0);
  else console.warn(`presets/${name}: ${result._0}`);
}
writeFileSync(
  join(out, "factory-presets.json"),
  JSON.stringify({ name: "factory", presets: presets.map(Preset.toJson) }),
);
console.log(`presets/ -> bundle/factory-presets.json (${presets.length} presets)`);
