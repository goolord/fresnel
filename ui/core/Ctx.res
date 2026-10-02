// What every control and page gets: the model, the presets, and the shared chrome.

type t = {
  model: ParamModel.t,
  pc: PatchConnection.t,
  status: Status.t,
  menu: Menu.t,
  presets: PresetStore.t,
  settings: Settings.t,
  // the host's parameter menu, on a double right-click
  hostMenu: HostMenu.t,
  // the stage: the design-sized element everything is laid out in, which dialogs cover
  stage: Dom.element,
  // design-to-screen scale of the stage
  scale: unit => float,
  // a short message near the bottom of the window, for a few seconds
  toast: string => unit,
}
