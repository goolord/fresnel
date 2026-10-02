// Preset file formats. A format reads a file into presets (one, or a bank of several) and may write
// them back; everything else (the store, the browser, the plugin's bank library, drag and drop)
// works with any format the plugin registers, by file extension. The template's own is JSON
// (`json` below); a plugin adds others in App.res, e.g. another synth's banks.

type t = {
  // what the Load button's menu and messages call it, e.g. "Nano preset"
  name: string,
  // lower case, with the dot: [".preset", ".bank"]
  extensions: array<string>,
  // the presets a file holds, or why it can't be read; fileName lets a format name a lone preset
  // after its file
  read: (~fileName: string, Uint8Array.t) => result<array<Preset.t>, string>,
  // a file holding these presets (one, or a bank), if the format can be written
  write: option<(~bankName: string, array<Preset.t>) => Uint8Array.t>,
}

@new external textDecoder: unit => {..} = "TextDecoder"
@new external textEncoder: unit => {..} = "TextEncoder"
let decodeUtf8 = (bytes: Uint8Array.t): string => textDecoder()["decode"](bytes)
let encodeUtf8 = (text: string): Uint8Array.t => textEncoder()["encode"](text)

let extensionOf = fileName =>
  switch fileName->String.lastIndexOf(".") {
  | i if i >= 0 => fileName->String.slice(~start=i)->String.toLowerCase
  | _ => ""
  }

// The template's format: a preset is a JSON object (Preset.toJson), and a bank is
// { "name": ..., "presets": [ ... ] }. Both use the same extension.
let jsonFormat = (~name, ~extension) => {
  name,
  extensions: [extension],
  read: (~fileName, bytes) =>
    switch JSON.parseOrThrow(decodeUtf8(bytes)) {
    | Object(o) =>
      switch o->Dict.get("presets") {
      | Some(Array(items)) =>
        let presets = items->Array.filterMap(Preset.fromJson)
        presets == [] ? Error("the bank holds no presets") : Ok(presets)
      | _ =>
        switch Preset.fromJson(Object(o)) {
        | Some(p) => Ok([o->Dict.get("name") == None ? {...p, name: Web.baseName(fileName)} : p])
        | None => Error("it isn't a preset")
        }
      }
    | _ => Error("it isn't a preset")
    | exception _ => Error("it isn't JSON")
    },
  write: Some(
    (~bankName, presets) =>
      encodeUtf8(
        switch presets {
        | [one] => JSON.stringify(Preset.toJson(one), ~space=2)
        | _ =>
          JSON.stringify(
            Object(
              Dict.fromArray([
                ("name", JSON.String(bankName)),
                ("presets", Array(presets->Array.map(Preset.toJson))),
              ]),
            ),
            ~space=2,
          )
        },
      ),
  ),
}

// The formats the plugin reads, its own first (App.res sets them).
let formats: ref<array<t>> = ref([])

let register = all => formats := all

let primary = () => formats.contents[0]

let forFile = fileName => {
  let ext = extensionOf(fileName)
  formats.contents->Array.find(f => f.extensions->Array.includes(ext))
}

let allExtensions = () => formats.contents->Array.flatMap(f => f.extensions)

// Reads a file with the format its extension names.
let read = (~fileName, bytes) =>
  switch forFile(fileName) {
  | Some(format) =>
    try format.read(~fileName, bytes) catch {
    | JsExn(e) => Error(e->JsExn.message->Option.getOr("it can't be read"))
    }
  | None => Error("it isn't a preset file this plugin knows")
  }
