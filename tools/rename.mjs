// Gives the template its own identity: the plugin's name, ID (reverse domain), manufacturer and
// four-letter codes in the manifest, the brand in the header (ui/plugin/Config.res), the preset
// format's name (ui/plugin/Formats.res) and the package name.
//
//   node tools/rename.mjs "My Plugin" com.me.myplugin ["Me"]     (or: just rename ...)
//
// The name names the built plugin (<name>.clap) and its settings folder; hosts know the plugin by
// its ID, so pick it once. The codes are made from the names; edit them in plugin.cmajorpatch if
// you want others.

import { readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const [name, id, manufacturerArg] = process.argv.slice(2);

if (!name || !id) {
  console.error('usage: node tools/rename.mjs "Plugin Name" com.example.plugin ["Manufacturer"]');
  process.exit(1);
}
if (!/^[A-Za-z0-9][A-Za-z0-9 ._-]*$/.test(name)) throw new Error("use letters, digits, spaces, dots, dashes or underscores in the name");
if (!/^[a-z0-9-]+(\.[a-z0-9-]+)+$/i.test(id)) throw new Error("the ID is a reverse domain name, like com.example.plugin");

const manufacturer = manufacturerArg || name;
// four letters for a code: the name's letters, padded
const code = (s, fallback) => (s.replace(/[^A-Za-z0-9]/g, "") + fallback).slice(0, 4).replace(/^./, (c) => c.toUpperCase());
const slug = name.toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "");

const edit = (path, change) => {
  const file = join(root, path);
  const before = readFileSync(file, "utf8");
  const after = change(before);
  if (after !== before) {
    writeFileSync(file, after);
    console.log(`updated ${path}`);
  }
};

edit("plugin.cmajorpatch", (s) => {
  const m = JSON.parse(s);
  const set = (key, value) => (s = s.replace(new RegExp(`("${key}"\\s*:\\s*)"[^"]*"`), `$1${JSON.stringify(value)}`));
  set("ID", id);
  set("name", name);
  set("manufacturer", manufacturer);
  if (m.description?.includes("nano-clap template")) set("description", `${name}, a Cmajor CLAP plugin`);
  set("manufacturerCode", code(manufacturer, "Mnfc"));
  set("pluginCode", code(name.split(/\s+/).pop(), "Plug"));
  return s;
});
edit("ui/plugin/Config.res", (s) => s.replace(/let brand = "[^"]*"/, `let brand = ${JSON.stringify(name.toLowerCase())}`));
edit("ui/plugin/Formats.res", (s) => s.replace(/~name="[^"]*"/, `~name=${JSON.stringify(name + " preset")}`));
edit("package.json", (s) => s.replace(/"name": "[^"]*"/, `"name": ${JSON.stringify(slug)}`));
edit("rescript.json", (s) => s.replace(/"name": "[^"]*"/, `"name": ${JSON.stringify(slug)}`));

console.log(`now ${name} (${id}), by ${manufacturer}`);
