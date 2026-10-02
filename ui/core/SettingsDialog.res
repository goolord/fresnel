// The settings dialog: settings that belong to the user rather than to a preset: the size of the
// interface (in the CLAP plugin, which sizes the window) and the theme, when the plugin has more
// than one. Both are kept in the settings file every instance shares.

open! Web

let percent = zoom => Float.toString(Math.round(zoom * 100.)) ++ " %"

let show = (settings: Settings.t, stage) => {
  let dialog = Dialog.make(stage, "Settings")
  let d = dialog.element

  let row = el("div", ~cls="drow", ~parent=d)
  el("span", ~text="interface size", ~parent=row)->ignore
  let steps = el("div", ~cls="seg", ~parent=row)
  let stepButtons = Settings.zoomSteps->Array.map(zoom => {
    let b = el("button", ~cls="btn", ~text=percent(zoom), ~parent=steps)
    b->onMouse(#click, _ => {
      settings->Settings.setZoom(zoom)
      settings->Settings.save("zoom", Number(zoom))
    })
    (zoom, b)
  })
  let note = el("div", ~cls="dnote", ~parent=d)
  let remember = el("button", ~cls="btn", ~text="Open new windows at this size", ~parent=d)
  remember->onMouse(#click, _ => settings->Settings.save("zoom", Number(settings.zoom)))

  let themeButtons = if Array.length(Config.themes) > 1 {
    let row = el("div", ~cls="drow", ~parent=d)
    el("span", ~text="theme", ~parent=row)->ignore
    let seg = el("div", ~cls="seg", ~parent=row)
    Config.themes->Array.map(theme => {
      let b = el("button", ~cls="btn", ~text=theme.name, ~parent=seg)
      b->onMouse(#click, _ => {
        Theme.set(theme)
        settings->Settings.save("theme", String(theme.name))
      })
      (theme, b)
    })
  } else {
    []
  }

  let update = () => {
    let available = settings->Settings.available
    let near = (a: float, b) => Math.abs(a - b) < 0.005
    stepButtons->Array.forEach(((zoom, b)) => {
      b->toggleClass("on", available && near(zoom, settings.zoom))
      b->toggleClass("off", !available)
    })
    let saved = settings->Settings.savedZoom
    note->setTextContent(
      available
        ? `This window is at ${percent(settings.zoom)}, new windows open at ${percent(
              saved,
            )}. Drag the window's corner to scale it in between.`
        : "Here the host sets the size of the window. In the CLAP plugin, this sets the size of the plugin window.",
    )
    themeButtons->Array.forEach(((theme, b)) => b->toggleClass("on", theme.name == Theme.current.contents.name))
    remember->setStyle(
      "display",
      available && !near(saved, settings.zoom) ? "inline-block" : "none",
    )
  }
  let stopListening = settings->Settings.listen(update)
  let stopTheme = Theme.onChange(_ => update())
  settings->Settings.refresh
  update()

  let close = () => {
    stopListening()
    stopTheme()
    dialog->Dialog.remove
  }
  dialog->Dialog.finish([("Close", close)], ~onEnter=close, ~close)->Array.forEach(focus)
}
