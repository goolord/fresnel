// The CLAP plugin's bank library (tools/clap/Library.h): the preset files (banks, or lone
// presets) in the folders the user adds in the preset browser, which the plugin scans for and
// copies, and the files opened in the browser, which it keeps. So the browser lists them without
// walking the folders each time, and still has them when the plugin window is opened again. The
// folders are a user setting ("presetFolders"). Elsewhere (cmaj play) nothing answers, and files
// opened in the browser last as long as the view.
//
// The plugin knows no formats: a scan asks for the extensions of the formats the plugin registers
// (PresetFormat), and a file is read with the format its extension names. Files are read from the
// plugin in parts, and parsed once per file and version.

type origin = Folder | Opened

type bank = {
  id: string,
  name: string,
  origin: origin,
  // the plugin's copy: its id and the file's extension, which names the format
  file: string,
  // where a folder's bank was found, and the folder
  path: string,
  folder: string,
  modified: float,
}

type t = {
  channel: HostChannel.t,
  settings: Settings.t,
  // whether the plugin has answered
  mutable available: bool,
  mutable banks: array<bank>,
  mutable scanning: bool,
  // whether this view has asked for the banks yet
  mutable scanned: bool,
  // whether the next list is this view's first: the folders are scanned then only if they (or the
  // extensions) aren't the ones the plugin last scanned
  mutable verifying: bool,
  listeners: array<unit => unit>,
  // reads in progress, by id: the parts so far, and what gets the file
  reads: Map.t<string, (array<Uint8Array.t>, option<Uint8Array.t> => unit)>,
}

// banks parsed already, by id and version: they're read again only when they change (an opened
// file's id is its contents' hash, so its extension is all that can change)
let parsed: Map.t<string, result<array<Preset.t>, string>> = Map.make()
let versionKey = bank =>
  bank.origin == Opened
    ? bank.id ++ PresetFormat.extensionOf(bank.file)
    : `${bank.id}@${Float.toString(bank.modified)}`

// A bank's file name for the format to read it by: its name, and its copy's extension.
let fileName = bank => bank.name ++ PresetFormat.extensionOf(bank.file)

//==============================================================================
// base64 (the parts the plugin sends and is sent)

let toBase64: Uint8Array.t => string = %raw(`bytes => {
  let s = ""
  for (let i = 0; i < bytes.length; i += 32768) s += String.fromCharCode (...bytes.subarray (i, i + 32768))
  return btoa (s)
}`)

let fromBase64: string => Uint8Array.t = %raw(`s => Uint8Array.from (atob (s), c => c.charCodeAt (0))`)

@send external setBytes: (Uint8Array.t, Uint8Array.t, int) => unit = "set"

//==============================================================================

let num = (d, key) =>
  switch d->Dict.get(key) {
  | Some(JSON.Number(x)) => x
  | _ => 0.
  }

let bankOf = (json: JSON.t) =>
  switch json {
  | Object(d) if Preset.string(d, "id") != "" =>
    Some({
      id: Preset.string(d, "id"),
      name: Preset.string(d, "name"),
      origin: Preset.string(d, "origin") == "opened" ? Opened : Folder,
      file: Preset.string(d, "file"),
      path: Preset.string(d, "path"),
      folder: Preset.string(d, "folder"),
      modified: num(d, "modified"),
    })
  | _ => None
  }

let changed = t => t.listeners->Array.forEach(fn => fn())

let request = (t, what, args) => t.channel->HostChannel.request(what ++ "=" ++ JSON.stringify(Object(Dict.fromArray(args))))

let onRead = (t, d: dict<JSON.t>) => {
  let id = Preset.string(d, "id")
  t.reads
  ->Map.get(id)
  ->Option.forEach(((parts, finish)) =>
    switch d->Dict.get("data") {
    | Some(String(data)) =>
      parts->Array.push(fromBase64(data))
      let part = Float.toInt(num(d, "part"))
      let count = Float.toInt(num(d, "parts"))
      if part + 1 < count {
        request(t, "read", [("id", JSON.String(id)), ("part", Number(Int.toFloat(part + 1)))])
      } else {
        t.reads->Map.delete(id)->ignore
        let all = Uint8Array.fromLength(parts->Array.reduce(0, (n, p) => n + TypedArray.length(p)))
        parts->Array.reduce(0, (at, p) => {
          all->setBytes(p, at)
          at + TypedArray.length(p)
        })->ignore
        finish(Some(all))
      }
    | _ =>
      t.reads->Map.delete(id)->ignore
      finish(None)
    }
  )
}

let settingKey = "presetFolders"

let folders = t =>
  switch t.settings->Settings.savedValue(settingKey) {
  | Some(Array(items)) => Preset.strings(items)
  | _ => []
  }

// What a scan looks for: the plugin's formats' extensions, less .json (too many other things are
// JSON; a .json file can still be opened in the browser).
let extensions = () => {
  let all = PresetFormat.allExtensions()->Array.map(String.toLowerCase)
  all->Array.filterWithIndex((e, i) => e != ".json" && all->Array.indexOf(e) == i)
}

let scan = t => {
  t.scanned = true
  t.scanning = true
  changed(t)
  request(t, "scan", [("folders", Preset.stringsJson(folders(t))), ("extensions", Preset.stringsJson(extensions()))])
}

let onReply = (t, reply: dict<JSON.t>) =>
  switch (reply->Dict.get("read"), reply->Dict.get("banks")) {
  | (Some(Object(d)), _) => onRead(t, d)
  | (_, Some(Array(banks))) =>
    t.available = true
    t.scanning = false
    t.banks = banks->Array.filterMap(bankOf)
    changed(t)
    // the first list: scan if the plugin hasn't walked these folders for these extensions (a
    // folder added since, a format the plugin reads now, or a library from before it noted them);
    // otherwise its cache is what the browser shows
    if t.verifying {
      t.verifying = false
      let before = key =>
        switch reply->Dict.get(key) {
        | Some(Array(items)) => Some(Preset.strings(items))
        | _ => None
        }
      if folders(t) != [] && (before("scanned") != Some(folders(t)) || before("extensions") != Some(extensions())) {
        scan(t)
      }
    }
  | _ =>
    t.scanning = false
    changed(t)
  }

let make = (pc, settings) => {
  let t = {
    channel: HostChannel.make(pc, "library"),
    settings,
    available: false,
    banks: [],
    scanning: false,
    scanned: false,
    verifying: false,
    listeners: [],
    reads: Map.make(),
  }
  t.channel->HostChannel.listen(onReply(t, _))
  t
}

let dispose = t => t.channel->HostChannel.dispose

let listen = (t, fn) => t.listeners->Array.push(fn)

// The banks as the plugin last listed them. The first time the view asks, the folders are
// scanned only if the plugin hasn't scanned these ones yet (see onReply); a scan is otherwise up
// to the user ("look again") or to a change of folders.
let refresh = t => {
  if !t.scanned {
    t.scanned = true
    t.verifying = true
  }
  t.channel->HostChannel.request("list")
}

let setFolders = (t, list) => {
  t.settings->Settings.save(settingKey, Preset.stringsJson(list))
  scan(t)
}

// A folder as typed or pasted: without quotes around it or a slash at the end.
let cleanFolder = s => {
  let s = s->String.trim->String.replaceRegExp(/^["']|["']$/g, "")->String.trim
  String.length(s) > 3 ? s->String.replaceRegExp(/[\\/]+$/, "") : s
}

let addFolder = (t, folder) => {
  let folder = cleanFolder(folder)
  let list = folders(t)
  if folder != "" && !(list->Array.includes(folder)) {
    setFolders(t, [...list, folder])
  }
}

let removeFolder = (t, folder) => setFolders(t, folders(t)->Array.filter(f => f != folder))

// A bank's file, read from the plugin.
let read = (t, id) =>
  Promise.make((resolve, _) => {
    t.reads->Map.set(id, ([], resolve))
    request(t, "read", [("id", JSON.String(id)), ("part", Number(0.))])
  })

// The presets of a bank, parsed once per version.
let presets = async (t, bank) =>
  switch parsed->Map.get(versionKey(bank)) {
  | Some(result) => result
  | None =>
    let result = switch await read(t, bank.id) {
    | Some(bytes) => PresetFormat.read(~fileName=fileName(bank), bytes)
    | None => Error("the plugin couldn't read its copy")
    }
    parsed->Map.set(versionKey(bank), result)
    result
  }

// An opened file's id: its contents' hash (two 32-bit FNV-1a), so opening it again finds it.
let hashBytes: (Uint8Array.t, int) => string = %raw(`(bytes, seed) => {
  let h = seed >>> 0
  for (let i = 0; i < bytes.length; ++i) h = Math.imul (h ^ bytes[i], 16777619) >>> 0
  return h.toString (16).padStart (8, "0")
}`)

let idOf = bytes => "o" ++ hashBytes(bytes, 0x811c9dc5) ++ hashBytes(bytes, 0x050c5d1f)

let partSize = 384 * 1024

// Keeps a file opened in the browser, already parsed into presets, under its extension (which
// names its format when it's read back); returns its id.
let keep = (t, ~name, ~ext, bytes: Uint8Array.t, presets) => {
  let id = idOf(bytes)
  parsed->Map.set(id ++ ext, Ok(presets))
  let length = TypedArray.length(bytes)
  let parts = Math.Int.max(1, (length + partSize - 1) / partSize)
  for part in 0 to parts - 1 {
    let slice = bytes->TypedArray.subarray(~start=part * partSize, ~end=Math.Int.min(length, (part + 1) * partSize))
    request(
      t,
      "put",
      [
        ("id", JSON.String(id)),
        ("name", String(name)),
        ("ext", String(ext)),
        ("part", Number(Int.toFloat(part))),
        ("parts", Number(Int.toFloat(parts))),
        ("data", String(toBase64(slice))),
      ],
    )
  }
  id
}

let remove = (t, id) => t.channel->HostChannel.request("remove=" ++ id)
