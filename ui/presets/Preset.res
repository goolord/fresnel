// A preset: a name and what describes it (author, category, tags, a description), and the values
// of the parameters by id. Whatever a file format holds, it is read into these (PresetFormat), so
// the store, the browser and the dialogs never deal with formats.
//
// Values are endpoint values (Param.res); a parameter a preset doesn't mention is at its default
// when it loads, and ids the plugin doesn't know are kept but ignored, so presets survive
// parameters being added or removed.

type t = {
  name: string,
  author: string,
  category: string,
  tags: array<string>,
  description: string,
  values: dict<float>,
  // anything else the plugin keeps with a preset (stored-state values: drawn tables, a sample...)
  extra: dict<JSON.t>,
}

let maxNameLength = 48

let make = (~name="Init", ~author="", ~category="", ~tags=[], ~description="", ~extra=Dict.make(), values) => {
  name,
  author,
  category,
  tags,
  description,
  values,
  extra,
}

// The parameters' values at their defaults.
let init = (defs: array<Param.t>) => make(defs->Array.map(d => (d.id, d.init))->Dict.fromArray)

// The values to send for a preset: every parameter, at the preset's value or else its default.
let resolve = (p, defs: array<Param.t>) =>
  defs->Array.map(d => (d.id, p.values->Dict.get(d.id)->Option.mapOr(d.init, d.clamp)))->Map.fromArray

// Whether the model's values are the preset's (to within float32 rounding).
let matches = (p, defs: array<Param.t>, get: string => float) =>
  defs->Array.every(d => {
    let want = p.values->Dict.get(d.id)->Option.mapOr(d.init, d.clamp)
    Math.abs(get(d.id) - want) <= 1e-6 * Math.max(1., Math.abs(want))
  })

// "Pad, warm" from tags typed with commas.
let parseTags = text =>
  text->String.split(",")->Array.map(String.trim)->Array.filter(t => t != "")

let safeFileName = name => {
  let s = name->String.replaceRegExp(/[\\\/:*?"<>|]+/g, "_")->String.trim
  s == "" ? "preset" : s
}

//==============================================================================
// JSON, the template's own format (PresetFormat.json) and the stored state's

let valuesJson = (values: dict<float>) => JSON.Object(values->Dict.mapValues(x => JSON.Number(x)))

// the finite numbers (and switches) of a JSON object of values
let valuesFromJson = (json: JSON.t) =>
  switch json {
  | Object(v) =>
    v
    ->Dict.toArray
    ->Array.filterMap(((id, x)) =>
      switch x {
      | Number(x) if Float.isFinite(x) => Some((id, x))
      | Boolean(on) => Some((id, on ? 1. : 0.))
      | _ => None
      }
    )
    ->Dict.fromArray
  | _ => Dict.make()
  }

let strings = (items: array<JSON.t>) =>
  items->Array.filterMap(x =>
    switch x {
    | String(s) => Some(s)
    | _ => None
    }
  )
let stringsJson = list => JSON.Array(list->Array.map(s => JSON.String(s)))

let toJson = p =>
  JSON.Object(
    Dict.fromArray([
      ("name", JSON.String(p.name)),
      ("author", String(p.author)),
      ("category", String(p.category)),
      ("tags", stringsJson(p.tags)),
      ("description", String(p.description)),
      ("values", valuesJson(p.values)),
      ...Dict.keysToArray(p.extra)->Array.length > 0 ? [("extra", JSON.Object(p.extra))] : [],
    ]),
  )

let string = (o, key) =>
  switch o->Dict.get(key) {
  | Some(JSON.String(s)) => s
  | _ => ""
  }

let fromJson = (json: JSON.t) =>
  switch json {
  | Object(o) =>
    Some({
      name: switch string(o, "name") {
      | "" => "Untitled"
      | name => name
      },
      author: string(o, "author"),
      category: string(o, "category"),
      tags: switch o->Dict.get("tags") {
      | Some(Array(tags)) => strings(tags)
      | _ => []
      },
      description: string(o, "description"),
      values: o->Dict.get("values")->Option.mapOr(Dict.make(), valuesFromJson),
      extra: switch o->Dict.get("extra") {
      | Some(Object(extra)) => extra
      | _ => Dict.make()
      },
    })
  | _ => None
  }

// The preset without its values: what the stored state keeps of the current one (the host keeps
// the parameters).
let infoJson = p => toJson({...p, values: Dict.make()})
