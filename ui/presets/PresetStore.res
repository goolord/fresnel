// The current preset as the view sees it: its name and description (which the patch's stored
// state keeps, so the host saves them with the session; the host saves the parameters on its own),
// whether the parameters still match it, and the list the header's arrows step through (the
// factory presets, or the bank last opened).
//
// Factory presets are the files in presets/, which tools/bundle.mjs gathers into
// bundle/factory-presets.json (a JSON bank) for the view and the worker to read.

let factoryPath = "bundle/factory-presets.json"
let storedKey = "preset"

type t = {
  pc: PatchConnection.t,
  model: ParamModel.t,
  defs: array<Param.t>,
  message: string => unit,
  mutable current: Preset.t,
  // what the arrows step through, its name, and the current preset's place in it
  mutable list: array<Preset.t>,
  mutable listName: string,
  mutable index: option<int>,
  mutable factory: array<Preset.t>,
  // whether the factory presets have been read (the browser shows them as loading until then)
  mutable factoryRead: bool,
  listeners: array<unit => unit>,
  // what the view last stored, to tell the host's echo from a new value
  mutable stored: option<string>,
  mutable stateListener: option<PatchConnection.storedStateEvent => unit>,
  // whether the parameters have moved away from the preset, as last worked out
  mutable dirty: bool,
}

let make = (pc, model, ~onMessage) => {
  let defs = model->ParamModel.all
  {
    pc,
    model,
    defs,
    message: onMessage,
    current: Preset.init(defs),
    list: [],
    listName: "",
    index: None,
    factory: [],
    factoryRead: false,
    listeners: [],
    stored: None,
    stateListener: None,
    dirty: false,
  }
}

let changed = t => t.listeners->Array.forEach(fn => fn())

// Calls fn when the preset, its details, its list or whether it's dirty change.
let onChanged = (t, fn) => t.listeners->Array.push(fn)

let name = t => t.current.name

let isDirty = t => t.dirty

let refreshDirty = t => {
  let dirty = !Preset.matches(t.current, t.defs, ParamModel.get(t.model, _))
  if dirty != t.dirty {
    t.dirty = dirty
    changed(t)
  }
}

// The stored state: the current preset, and the list the arrows step through, by name, with its
// presets if given.
let stateJson = (~current: Preset.t, ~listName, ~index, ~list=[]) =>
  JSON.Object(
    Dict.fromArray([
      ("info", Preset.infoJson(current)),
      ("values", Preset.valuesJson(current.values)),
      ("list", String(listName)),
      ("index", index->Option.mapOr(JSON.Null, i => Number(Int.toFloat(i)))),
      ...list != [] ? [("presets", JSON.Array(list->Array.map(Preset.toJson)))] : [],
    ]),
  )

// The current preset, and the list the arrows step through: the factory's by name, any other
// (a bank the user loaded) in full, so that a session comes back with it.
let store = t => {
  let ownList = t.listName != "factory"
  let json = stateJson(~current=t.current, ~listName=t.listName, ~index=t.index, ~list=ownList ? t.list : [])
  let text = JSON.stringify(json)
  t.stored = Some(text)
  t.pc->PatchConnection.sendStoredStateValue(storedKey, json)
}

// Puts a preset into the patch: every parameter (those it doesn't hold at their defaults), and
// its details into the stored state. ~list is what the arrows step through from it.
let load = (t, preset: Preset.t, ~list=?, ~listName=?, ~index=?) => {
  t.current = preset
  list->Option.forEach(list => t.list = list)
  listName->Option.forEach(name => t.listName = name)
  t.index = index
  t.model->ParamModel.setAll(Preset.resolve(preset, t.defs))
  t.dirty = false
  store(t)
  changed(t)
}

let select = (t, i) =>
  t.list[i]->Option.forEach(p => load(t, p, ~index=i))

// The next or previous preset in the list, round the ends.
let step = (t, d) => {
  let n = Array.length(t.list)
  if n > 0 {
    let i = switch t.index {
    | Some(i) => mod(mod(i + d, n) + n, n)
    | None => d > 0 ? 0 : n - 1
    }
    select(t, i)
  }
}

let initCurrent = t => load(t, Preset.init(t.defs), ~index=?None)

// Changes the current preset's details (not its values, which are the parameters').
let setInfo = (t, info: Preset.t) => {
  t.current = {...info, values: t.current.values}
  store(t)
  changed(t)
}

let rename = (t, name) => {
  let name = String.trim(name)->String.slice(~start=0, ~end=Preset.maxNameLength)
  if name != "" {
    setInfo(t, {...t.current, name})
  }
}

// The current preset with the parameters as they are now (what Save writes).
let snapshot = t => {...t.current, values: t.model->ParamModel.snapshot}

// Plays a preset without making it the current one (the browser, while the user clicks through
// presets); restore puts back what was playing, as snapshot captured it, with its details.
let preview = (t, preset) => t.model->ParamModel.setAll(Preset.resolve(preset, t.defs))

let restore = (t, kept: Preset.t, ~current: Preset.t) => {
  t.model->ParamModel.setAll(Preset.resolve(kept, t.defs))
  t.current = current
  refreshDirty(t)
  changed(t)
}

// After saving: the parameters are now the preset's.
let markSaved = t => {
  t.current = snapshot(t)
  t.dirty = false
  store(t)
  changed(t)
}

//==============================================================================
// files

let download = (bytes, filename) => {
  open! Web
  let url = createObjectURL(makeBlob([bytes], {mimeType: "application/octet-stream"}))
  let a = el("a", ~parent=document->body)
  a->setHref(url)
  a->setDownload(filename)
  a->click
  setTimeout(() => {
    revokeObjectURL(url)
    a->remove
  }, 1000)->ignore
}

let extension = (format: PresetFormat.t) => format.extensions[0]->Option.getOr("")

// Saves the current preset as a file in the plugin's own format.
let save = t =>
  PresetFormat.primary()->Option.forEach(format =>
    format.write->Option.forEach(write => {
      let p = snapshot(t)
      download(write(~bankName="", [p]), Preset.safeFileName(p.name) ++ extension(format))
      markSaved(t)
    })
  )

// Loads presets from a file: a lone preset loads; a bank becomes the list and its first preset
// loads. Returns the presets, or None if the file couldn't be read (the user is told why).
let loadBytes = (t, ~fileName, bytes) =>
  switch PresetFormat.read(~fileName, bytes) {
  | Ok([one]) =>
    load(t, one, ~index=?None)
    Some([one])
  | Ok(presets) =>
    presets[0]->Option.forEach(first =>
      load(t, first, ~list=presets, ~listName=Web.baseName(fileName), ~index=0)
    )
    t.message(`${Web.baseName(fileName)}: ${Int.toString(Array.length(presets))} presets`)
    Some(presets)
  | Error(why) =>
    t.message(`Couldn't load ${fileName}: ${why}`)
    None
  }

let loadFile = async (t, file) =>
  switch await Web.readBytes(file) {
  | Ok(bytes) => loadBytes(t, ~fileName=file->Web.fileName, bytes)->ignore
  | Error(why) => t.message(why)
  }

//==============================================================================
// the stored state and the factory presets

let onState = (t, {key, value}: PatchConnection.storedStateEvent) =>
  if key == storedKey && t.stored != Some(JSON.stringify(value)) {
    switch value {
    | Object(o) =>
      let info = o->Dict.get("info")->Option.flatMap(Preset.fromJson)
      let values = o->Dict.get("values")->Option.map(Preset.valuesFromJson)
      info->Option.forEach(info => {
        t.current = {...info, values: values->Option.getOr(Dict.make())}
        t.listName = Preset.string(o, "list")
        switch o->Dict.get("presets") {
        | Some(Array(items)) => t.list = items->Array.filterMap(Preset.fromJson)
        | _ if t.listName == "factory" && t.factoryRead => t.list = t.factory
        | _ => ()
        }
        t.index = switch o->Dict.get("index") {
        | Some(Number(i)) => Some(Float.toInt(i))
        | _ => None
        }
        t.stored = Some(JSON.stringify(value))
        refreshDirty(t)
        changed(t)
      })
    | _ => ()
    }
  }

// The factory presets, as tools/bundle.mjs gathered them.
let readFactory = async pc =>
  switch await Resources.readText(pc, factoryPath) {
  | Some(text) =>
    switch PresetFormat.readJson(~fileName="factory", JSON.parseOrThrow(text)) {
    | Ok(presets) => presets
    | Error(_) => []
    | exception _ => []
    }
  | None => []
  }

let start = t => {
  let listener = ev => onState(t, ev)
  t.stateListener = Some(listener)
  t.pc->PatchConnection.addStoredStateValueListener(listener)
  // the parameters moving away from the preset (or back) mark it
  t.model->ParamModel.listenAny(Web.perFrame(() => refreshDirty(t))->(f => _ => f()))
  readFactory(t.pc)
  ->Promise.thenResolve(presets => {
    t.factory = presets
    t.factoryRead = true
    if t.list == [] {
      t.list = presets
      t.listName = "factory"
      if t.index == None {
        t.index = presets->Array.findIndex(p => p.name == t.current.name)->(i => i >= 0 ? Some(i) : None)
      }
    }
    changed(t)
  })
  ->Promise.ignore
}

// The stored state from requestFullStoredState.
let loadState = (t, values: dict<JSON.t>) =>
  values->Dict.get(storedKey)->Option.forEach(value => onState(t, {key: storedKey, value}))

let dispose = t =>
  t.stateListener->Option.forEach(l => t.pc->PatchConnection.removeStoredStateValueListener(l))
