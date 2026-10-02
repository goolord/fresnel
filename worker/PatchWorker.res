// The patch worker: runs whenever the patch is created, with or without the view open (in the
// CLAP plugin it runs in QuickJS, see tools/clap-patch.mjs). The host restores the parameters
// itself; anything else the DSP needs from the stored state (drawn tables, samples, tunings...)
// has to be pushed into the patch from here.
//
// A new instance, whose stored state has no preset yet, starts on the first factory preset.

open PatchConnection

let start = async pc =>
  switch (await PresetStore.readFactory(pc))[0] {
  | Some(first) =>
    let defs = Param.makeAll(Params.all)
    Preset.resolve(first, defs)->Map.forEachWithKey((value, id) => pc->sendEventOrValue(id, value))
    pc->sendStoredStateValue(
      PresetStore.storedKey,
      JSON.Object(
        Dict.fromArray([
          ("info", Preset.infoJson(first)),
          ("values", Object(first.values->Dict.mapValues(x => JSON.Number(x)))),
          ("list", String("factory")),
          ("index", Number(0.)),
        ]),
      ),
    )
  | None => ()
  }

let default = pc => {
  let checked = ref(false)
  pc->addStoredStateValueListener(({key, value}) =>
    // The patch answers the request below even when there's no value, which is a new instance. (A
    // host restores a session before the worker starts, or later, replacing what this stores.)
    if key == PresetStore.storedKey && !checked.contents {
      checked := true
      switch value {
      | Object(_) => ()
      // Not from inside this callback: Cmajor replays the replies that came while the worker was
      // starting with a lock held, and storing a value sends it back to the worker, which needs
      // that lock.
      | _ => setTimeout(() => start(pc)->Promise.ignore, 0)->ignore
      }
    }
  )
  pc->requestStoredStateValue(PresetStore.storedKey)
}
