// The parameter model: the view's copy of every parameter's value (the endpoint's value, see
// Param.res), kept in step with the patch both ways, with listeners for changes.

type t = {
  pc: PatchConnection.t,
  defs: Map.t<string, Param.t>,
  values: Map.t<string, float>,
  listeners: Map.t<string, array<unit => unit>>,
  anyListeners: array<string => unit>,
  onParam: PatchConnection.parameterEvent => unit,
}

let notifyListeners = (listeners, anyListeners, id) => {
  listeners->Map.get(id)->Option.forEach(fns => fns->Array.forEach(fn => fn()))
  anyListeners->Array.forEach(fn => fn(id))
}

let make = (pc, defs: array<Param.t>) => {
  let defsById = defs->Array.map(d => (d.id, d))->Map.fromArray
  let values = defs->Array.map(d => (d.id, d.init))->Map.fromArray
  let listeners = Map.make()
  let anyListeners = []

  let onParam = ({endpointID, value}: PatchConnection.parameterEvent) =>
    defsById
    ->Map.get(endpointID)
    ->Option.forEach(d => {
      let x = d.isInt ? Math.round(value) : value
      switch values->Map.get(d.id) {
      | Some(old) if old == x => ()
      | _ =>
        values->Map.set(d.id, x)
        notifyListeners(listeners, anyListeners, d.id)
      }
    })

  pc->PatchConnection.addAllParameterListener(onParam)
  {pc, defs: defsById, values, listeners, anyListeners, onParam}
}

// The patch's values, from a full stored state: it lists the parameters that differ from
// their defaults, which the model starts with.
let loadParameters = (t, parameters: array<PatchConnection.namedValue>) =>
  parameters->Array.forEach(({name, value}) => t.onParam({endpointID: name, value}))

let dispose = t => t.pc->PatchConnection.removeAllParameterListener(t.onParam)

let def = (t, id) =>
  switch t.defs->Map.get(id) {
  | Some(d) => d
  | None => JsError.panic("unknown parameter " ++ id)
  }

let get = (t, id) => t.values->Map.get(id)->Option.getOr(0.)

// The parameter's value as the status line and the readouts show it.
let longText = (t, id) => def(t, id).longText(get(t, id))
let shortText = (t, id) => def(t, id).shortText(get(t, id))
// Several parameters' long texts, for the status line.
let statusText = (t, ids) => ids->Array.map(longText(t, _))->Array.join("    ")

let listen = (t, id, fn) =>
  switch t.listeners->Map.get(id) {
  | Some(fns) => fns->Array.push(fn)
  | None => t.listeners->Map.set(id, [fn])
  }

// Calls fn whenever one of these parameters changes.
let listenEach = (t, ids, fn) => ids->Array.forEach(id => listen(t, id, fn))

let listenAny = (t, fn) => t.anyListeners->Array.push(fn)

let notify = (t, id) => notifyListeners(t.listeners, t.anyListeners, id)

let set = (t, id, x) =>
  t.defs
  ->Map.get(id)
  ->Option.forEach(d => {
    let x = d.clamp(x)
    if get(t, id) != x {
      t.values->Map.set(id, x)
      t.pc->PatchConnection.sendEventOrValue(id, x)
      notify(t, id)
    }
  })

let beginGesture = (t, id) => t.pc->PatchConnection.sendParameterGestureStart(id)
let endGesture = (t, id) => t.pc->PatchConnection.sendParameterGestureEnd(id)

let gestureSet = (t, id, x) => {
  beginGesture(t, id)
  set(t, id, x)
  endGesture(t, id)
}

// Pushes a whole set of values (a loaded preset). Every endpoint is sent, even if unchanged, so the
// patch is guaranteed to match; listeners hear of the changed ones, once every value is in place.
let setAll = (t, values: Map.t<string, float>) => {
  let changed = []
  values->Map.forEachWithKey((x, id) =>
    t.defs
    ->Map.get(id)
    ->Option.forEach(d => {
      let x = d.clamp(x)
      if get(t, id) != x {
        changed->Array.push(id)
      }
      t.values->Map.set(id, x)
      t.pc->PatchConnection.sendEventOrValueNow(id, x)
    })
  )
  changed->Array.forEach(id => notify(t, id))
}

// Every parameter's value, by id.
let snapshot = t => t.values->Map.entries->Dict.fromIterator

// Every parameter at its default.
let defaults = t => t.defs->Map.values->Iterator.toArray->Array.map(d => (d.id, d.init))->Map.fromArray

// The defs in the plugin's order.
let all = t => t.defs->Map.values->Iterator.toArray->Array.toSorted((a, b) => Int.toFloat(a.index - b.index))
