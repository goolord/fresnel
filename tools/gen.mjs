// Generates the parameter plumbing from the plugin's parameter list, ui/plugin/Params.res (compile
// the view first: `npm run res`), so that the view, the host and the DSP agree on every parameter:
//
//   dsp/Params.cmajor   - processor Params: an endpoint per parameter (its name, range, default,
//                         unit or value names, which hosts see), sending params::Values (every
//                         parameter's plain value, by name) whenever one changes; and namespace
//                         params: that struct, its defaults, and names for each list's values
//                         (params::<id>::<value>) for the DSP to compare against
//   the manifest's source list (every .cmajor file under dsp/: Cmajor manifests take no
//                         wildcards) and its view size, from ui/plugin/Config.res
//
// run: node tools/gen.mjs   (`just gen`; every build runs it)

import { writeFileSync, readFileSync, existsSync, readdirSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const load = (path) => import(pathToFileURL(join(root, path)).href);

const { all: specs } = await load("ui/plugin/Params.res.mjs");
const { makeAll } = await load("ui/core/Param.res.mjs");
const Config = await load("ui/plugin/Config.res.mjs");
const manifestPath = join(root, "plugin.cmajorpatch");

// Writes a file unless it already holds this text (compared without CRLFs, which git may check
// out), so an unchanged file keeps its timestamp and doesn't show up as modified.
function writeGenerated(path, text) {
  if (existsSync(path) && readFileSync(path, "utf8").replace(/\r\n/g, "\n") === text) return false;
  writeFileSync(path, text);
  return true;
}

// a number as Cmajor reads it; float literals as float32 ("f")
const num = (x) => {
  if (Number.isInteger(x)) return String(x);
  let s = String(Math.fround(x));
  if (!/[.e]/.test(s)) s += ".0";
  return s;
};
const cf = (x) => {
  if (!Number.isFinite(x)) throw new Error(`not a finite value: ${x}`);
  const s = num(x);
  return (/[.e]/.test(s) ? s : s + ".0") + "f";
};
const str = (s) => JSON.stringify(s);
// a float64 literal
const f64 = (x) => (/[.e]/.test(String(x)) ? String(x) : String(x) + ".0");

// a Cmajor identifier from a value name: "4/5 16ths" -> _4_5_16ths, "low shelf" -> lowShelf
const reserved = new Set(["bool", "break", "case", "const", "continue", "default", "do", "else", "event", "false", "for",
  "graph", "if", "import", "input", "int", "let", "loop", "namespace", "node", "output", "processor", "return", "stream",
  "struct", "switch", "true", "value", "var", "void", "while", "wrap", "clamp", "float", "string", "external", "on", "off",
  "in", "out", "connection", "using", "static_assert", "fixed", "enum", "operator", "public", "private"]);
// (numbers: "1/16" -> n1_16, "-2" -> minus2, "+1" -> plus1; Cmajor reserves a leading underscore)
function ident(label) {
  const sign = label.startsWith("-") || label.startsWith("−") ? "minus" : label.startsWith("+") ? "plus" : "";
  const words = label.replace(/[()'".,]/g, "").split(/[^A-Za-z0-9]+/).filter((w) => w);
  if (words.length === 0) return "value";
  if (/^[0-9]/.test(words[0])) return (sign || "n") + words.join("_");
  const s = words.map((w, i) => (i === 0 ? w[0].toLowerCase() + w.slice(1) : w[0].toUpperCase() + w.slice(1))).join("");
  return reserved.has(s) ? s + "_" : s;
}

const defs = makeAll(specs);
const ids = new Set();
const endpoints = [], handlers = [], fields = [], defaults = [], choices = [];

defs.forEach((d, index) => {
  if (!/^[A-Za-z_][A-Za-z0-9_]*$/.test(d.id)) throw new Error(`parameter id "${d.id}" isn't a Cmajor identifier`);
  if (ids.has(d.id)) throw new Error(`two parameters are called "${d.id}"`);
  ids.add(d.id);

  const spec = specs[index];
  const kind = spec.kind.TAG;
  const ann = [`name: ${str(d.name)}`];
  if (d.hidden) ann.push("automatable: false");

  if (kind === "Toggle") {
    ann.push(`min: 0`, `max: 1`, `init: ${Math.round(d.init)}`, `text: "off|on"`, "boolean: true");
    endpoints.push(`    input event int ${d.id} [[ ${ann.join(", ")} ]];`);
    handlers.push(`    event ${d.id} (int v)  { values.${d.id} = v != 0; out <- values; }`);
    fields.push(`        bool ${d.id};`);
    defaults.push(`        v.${d.id} = ${d.init !== 0};`);
  } else if (kind === "Choice") {
    ann.push(`min: ${d.min}`, `max: ${d.max}`, `init: ${Math.round(d.init)}`, `text: ${str(d.names.join("|"))}`);
    endpoints.push(`    input event int ${d.id} [[ ${ann.join(", ")} ]];`);
    handlers.push(`    event ${d.id} (int v)  { values.${d.id} = v; out <- values; }`);
    fields.push(`        int ${d.id};`);
    defaults.push(`        v.${d.id} = ${Math.round(d.init)};`);
    // the list's values by name
    const seen = new Set();
    const names = d.names.map((n, i) => {
      let name = ident(n);
      while (seen.has(name)) name += "_";
      seen.add(name);
      return `        let ${name} = ${i};`;
    });
    choices.push(`    /// ${d.name}: ${d.names.join(", ")}\n    namespace ${d.id}\n    {\n${names.join("\n")}\n    }`);
  } else {
    ann.push(`min: ${num(d.min)}`, `max: ${num(d.max)}`, `init: ${num(d.init)}`);
    if (d.unit !== undefined) ann.push(`unit: ${str(d.unit)}`);
    endpoints.push(`    input event float ${d.id} [[ ${ann.join(", ")} ]];`);
    // a logarithmic knob's endpoint holds its position; the DSP gets lo * (hi / lo) ^ position
    const plain = spec.kind._0.law === "Exp"
      ? `float (${f64(spec.kind._0.min)} * pow (${f64(spec.kind._0.max / spec.kind._0.min)}, float64 (v)))`
      : "v";
    handlers.push(`    event ${d.id} (float v)  { values.${d.id} = ${plain}; out <- values; }`);
    fields.push(`        float ${d.id};`);
    defaults.push(`        v.${d.id} = ${cf(d.plain(d.init))};`);
  }
});

const text = `//  Generated by tools/gen.mjs from ui/plugin/Params.res - do not edit by hand.

/// The plugin's parameters as plain values (a logarithmic knob's frequency or time rather than its
/// position, a list's index, a switch's bool), and the values of each list by name: compare
/// p.filterType with params::filterType::ladder.
namespace params
{
    struct Values
    {
${fields.join("\n")}
    }

    /// Every parameter at its default. Hosts don't send a parameter that was never changed, so a
    /// DSP starts from these.
    Values defaults()
    {
        Values v;
${defaults.join("\n")}
        return v;
    }

${choices.join("\n\n")}
}

/// The parameter endpoints, which hosts automate and save. Whenever one changes, all the values go
/// out together to whatever the graph connects \`out\` to.
processor Params
{
    output event params::Values out;

${endpoints.join("\n")}

    params::Values values;

    void init()     { values = params::defaults(); }

${handlers.join("\n")}
}
`;

const wrote = writeGenerated(join(root, "dsp", "Params.cmajor"), text);

// the manifest lists every source under dsp/ (the plugin's own first), and its view size follows the
// design size
const sources = (dir) =>
  readdirSync(join(root, dir), { withFileTypes: true })
    .sort((a, b) => Number(a.isDirectory()) - Number(b.isDirectory()) || a.name.localeCompare(b.name))
    .flatMap((e) => (e.isDirectory() ? sources(`${dir}/${e.name}`) : e.name.endsWith(".cmajor") ? [`${dir}/${e.name}`] : []));
const manifest = readFileSync(manifestPath, "utf8");
const listed = manifest.replace(/("source"\s*:\s*)\[[^\]]*\]/, `$1[ ${sources("dsp").map(str).join(", ")} ]`);
const sized = listed.replace(
  /("view"\s*:\s*\{[^}]*?"width"\s*:\s*)\d+(\s*,[^}]*?"height"\s*:\s*)\d+/,
  `$1${Config.designWidth}$2${Config.designHeight}`,
);
if (sized !== manifest) writeFileSync(manifestPath, sized);

console.log(`${defs.length} parameters${wrote ? " -> dsp/Params.cmajor" : " (dsp/Params.cmajor is unchanged)"}`);
