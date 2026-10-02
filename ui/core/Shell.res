// The frame every plugin's view lives in: pages on a fixed-size stage scaled to fit the window, a
// header (the plugin's name, the page tabs, the preset bar and the file buttons), a status line,
// toasts, drag and drop, and everything the web view needs smoothing over:
//
//  - The view is a custom element with a shadow root, so its styles stay its own, and it lets go of
//    the patch connection when Cmajor removes it (disconnectedCallback).
//  - Cmajor sets the manifest's size on the view as an inline style; the stylesheet overrides it so
//    that the stage can scale with the window (Style.css), and the page behind it gets the theme's
//    ground (it shows while a host resizes the window).
//  - The browser's own context menu, shortcuts (reload, print, find...) and page zoom are switched
//    off (BrowserChrome), keys typed into dialogs stay out of the host's way (Dialog), and the
//    host's parameter menu opens on a double right-click and closes on the next press (HostMenu).
//  - Parameters and stored state arrive in one message when the view opens, instead of a round
//    trip per parameter.
//  - Files dropped anywhere on the window load (presets, banks, or whatever the plugin handles
//    itself, see ~onDrop); with the preset browser open they're added to it instead.

open! Web

@val @scope("CSS") external cssSupports: (string, string) => bool = "supports"
let supportsZoom = cssSupports("zoom", "2")

// A page: its tab's label and tooltip, its hint for the status line when idle, what builds it, and
// what to do each time it's shown.
type page = {
  id: string,
  label: string,
  title: string,
  hint: string,
  build: (Ctx.t, element) => unit,
  onShow?: unit => unit,
}

type t = {
  showPage: string => unit,
  ctx: Ctx.t,
  // lets go of the patch connection
  dispose: unit => unit,
}

// Puts the theme's properties on the view's root.
let applyTheme = (host, theme) => Theme.properties(theme)->Array.forEach(((name, value)) => host->setStyle(name, value))

// ~onDrop takes a dropped or picked file that isn't a preset (true if it did), whose extensions
// are ~dropExtensions; ~buttons are more header buttons (text, tooltip, action), before Settings.
let make = (
  host,
  pc,
  ~specs: array<Param.spec>,
  ~pages: array<page>,
  ~onDrop: (Ctx.t, file) => bool=(_, _) => false,
  ~dropExtensions=[],
  ~dropText="Drop a preset or a bank",
  ~buttons: Ctx.t => array<(string, string, unit => unit)>=_ => [],
) => {
  let defs = Param.makeAll(specs)
  let model = ParamModel.make(pc, defs)

  let restoreBrowserChrome = BrowserChrome.install()
  let settings = Settings.make(pc)
  let hostMenu = HostMenu.make(pc)

  // the theme: the plugin's first, until the settings say otherwise
  let themeByName = name => Config.themes->Array.find(t => t.name == name)
  Theme.current := Config.themes[0]->Option.getOr(Theme.current.contents)
  let showTheme = theme => {
    applyTheme(host, theme)
    // the page around the view shows while a host resizes the window
    document->documentElement->setStyle("background", Theme.rgb(theme.ground))
  }
  showTheme(Theme.current.contents)
  let stopTheme = Theme.onChange(showTheme)
  let stopSettings = settings->Settings.listen(() =>
    themeByName(settings->Settings.string("theme", ~default=""))->Option.forEach(theme =>
      if theme !== Theme.current.contents {
        Theme.set(theme)
      }
    )
  )

  let shadow = host->attachShadow({mode: "open"})
  el("style", ~text=Style.all(), ~parent=shadow)->ignore
  let stage = el("div", ~cls="pv-stage", ~parent=shadow)
  let head = el("div", ~cls="pv-head", ~parent=stage)
  let msg = el("div", ~cls="pv-status", ~parent=stage)
  let status = Status.make(msg)
  let menu = Menu.make(stage, ~status)
  let scale = ref(1.)

  let toastEl = el("div", ~cls="toast")
  let toastTimer = ref(None)
  let toast = text => {
    toastEl->setTextContent(text)
    toastEl->addClass("on")
    toastTimer.contents->Option.forEach(clearTimeout)
    toastTimer := Some(setTimeout(() => toastEl->removeClass("on"), 3500))
  }

  let presets = PresetStore.make(pc, model, ~onMessage=toast)

  let ctx: Ctx.t = {
    model,
    pc,
    status,
    menu,
    presets,
    settings,
    hostMenu,
    stage,
    scale: () => scale.contents,
    toast,
  }

  //==============================================================================
  // pages

  let firstPage = pages[0]->Option.mapOr("", p => p.id)
  let pageEls = pages->Array.map(p => (p, el("div", ~cls=p.id == firstPage ? "pv-page on" : "pv-page", ~parent=stage)))
  let pageButtons: array<(string, element)> = []

  let showPage = id => {
    pageEls->Array.forEach(((p, e)) => e->toggleClass("on", p.id == id))
    pageButtons->Array.forEach(((p, b)) => b->toggleClass("on", p == id))
    menu->Menu.close
    pages
    ->Array.find(p => p.id == id)
    ->Option.forEach(p => {
      status->Status.setIdle(p.hint)
      p.onShow->Option.forEach(f => f())
    })
  }

  pageEls->Array.forEach(((p, e)) => p.build(ctx, e))

  //==============================================================================
  // header

  let button = (parent, text, title, onClick) => {
    let b = el("button", ~cls="btn", ~text, ~parent)
    b->onMouse(#click, _ => onClick())
    status->Status.hover(b, () => title)
    b
  }

  el("div", ~cls="brand", ~text=Config.brand, ~parent=head)->ignore
  // one page needs no tabs
  if Array.length(pages) > 1 {
    let pagesBar = el("div", ~cls="pages", ~parent=head)
    pages->Array.forEach(({id, label, title}) =>
      pageButtons->Array.push((id, button(pagesBar, label, title, () => showPage(id))))
    )
    pageButtons->Array.forEach(((id, b)) => b->toggleClass("on", id == firstPage))
  }
  el("div", ~cls="spacer", ~parent=head)->ignore

  // the preset bar: previous, the name (click for the list, double-click to rename), next
  let presetName = el("div", ~cls="name")
  let updatePresetBar = () => {
    presetName->setLabel(presets->PresetStore.name)
    presetName->toggleClass("dirty", presets->PresetStore.isDirty)
  }
  presets->PresetStore.onChanged(updatePresetBar)

  let openPresetMenu = () =>
    menu->Menu.show(
      presetName,
      presets.list->Array.mapWithIndex((p, i) => {Menu.label: p.name, value: i}),
      presets.index->Option.getOr(-1),
      i => presets->PresetStore.select(i),
    )

  let renamePreset = () =>
    Controls.editInPlace(
      presetName,
      presets->PresetStore.name,
      ~maxLength=Preset.maxNameLength,
      ~within=stage,
      ~commit=name => presets->PresetStore.rename(name),
    )

  let bar = el("div", ~cls="prog", ~parent=head)
  button(bar, "<", "Previous preset", () => presets->PresetStore.step(-1))->ignore
  bar->appendChild(presetName)
  presetName->onMouse(#click, _ => openPresetMenu())
  presetName->onMouse(#dblclick, _ => renamePreset())
  status->Status.hover(presetName, () =>
    `${presets.current.name}${presets->PresetStore.isDirty ? " (changed)" : ""}: click to pick a preset${presets.listName == ""
        ? ""
        : " from " ++ presets.listName}, double-click to rename it`
  )
  button(bar, ">", "Next preset", () => presets->PresetStore.step(1))->ignore

  let browser = PresetBrowser.make(ctx)
  let browse = () =>
    if !(browser->PresetBrowser.isOpen) {
      browser->PresetBrowser.show
    }
  button(head, "Browse", "Search the presets by name, category, tags and author (ctrl+F)", browse)->ignore
  let onShortcut = k =>
    if k->commandKey && k->key->String.toLowerCase == "f" {
      k->preventDefault
      browse()
    }
  document->onDocumentKeyDown(onShortcut)

  // a dropped or picked file: a preset or bank, or whatever the plugin takes itself
  let loadFile = file =>
    if !onDrop(ctx, file) {
      presets->PresetStore.loadFile(file)->Promise.ignore
    }
  let accept = [...PresetFormat.allExtensions(), ...dropExtensions]->Array.join(",")
  let pickFile = FilePicker.make(stage, ~accept, loadFile)
  let formatNames = PresetFormat.formats.contents->Array.map(f => f.name)->Array.join(", ")
  button(head, "Load", `Load a preset or bank (${formatNames}). You can also drop files onto the window.`, pickFile)->ignore
  button(head, "Save", "Save this preset as a file", () => presets->PresetStore.save)->ignore
  button(head, "Info", "Name, author, category, tags and description of this preset", () => InfoDialog.show(ctx))->ignore
  button(head, "Init", "Reset every parameter to its default", () => presets->PresetStore.initCurrent)->ignore
  buttons(ctx)->Array.forEach(((text, title, action)) => button(head, text, title, action)->ignore)
  button(head, "⚙", "Settings: the size of the interface, and the theme", () =>
    SettingsDialog.show(settings, stage)
  )->addClass("icon")

  stage->appendChild(toastEl)

  //==============================================================================
  // drop zone: the whole window takes files (the browser takes them while it is open)

  let drop = el("div", ~cls="drop", ~parent=stage)
  let dropLabel = el("div", ~parent=drop)
  // dragenter and dragleave come for every child the pointer crosses: count them
  let depth = ref(0)
  host->onDrag(#dragenter, e => {
    e->preventDefault
    depth := depth.contents + 1
    dropLabel->setTextContent(
      browser->PresetBrowser.isOpen ? "Drop presets or banks to browse them" : dropText,
    )
    drop->addClass("on")
  })
  host->onDrag(#dragleave, e => {
    e->preventDefault
    depth := depth.contents - 1
    if depth.contents <= 0 {
      depth := 0
      drop->removeClass("on")
    }
  })
  // (without this, the web view would open a dropped file itself)
  host->onDrag(#dragover, e => e->preventDefault)
  host->onDrag(#drop, e => {
    e->preventDefault
    depth := 0
    drop->removeClass("on")
    e
    ->dataTransfer
    ->Option.forEach(d => {
      let files = d->transferredFiles->filesToArray
      if browser->PresetBrowser.isOpen {
        browser->PresetBrowser.addFiles(files)
      } else {
        files[0]->Option.forEach(loadFile)
      }
    })
  })

  //==============================================================================
  // scaling: the stage keeps the design size, scaled to fit the window and centred in it. CSS zoom
  // lays the page out again at the scale, so text and lines land on whole device pixels at any
  // size (a transform scales what was laid out at the design size, and at 125 % or 150 % text
  // sits up to half a design pixel off and blurs); a transform only where zoom isn't supported.

  let layout = () => {
    let orDesign = (x, design) => x == 0. ? design : x
    let w = host->clientWidth->orDesign(Style.designWidth)
    let h = host->clientHeight->orDesign(Style.designHeight)
    let s = Math.min(w / Style.designWidth, h / Style.designHeight)
    scale := s
    let ox = Math.max(0., (w - Style.designWidth * s) / 2.)
    let oy = Math.max(0., (h - Style.designHeight * s) / 2.)
    if supportsZoom {
      // (a zoomed element's own left and top are zoomed too)
      stage->setStyle("zoom", Float.toString(s))
      stage->setStyle("left", px(ox / s))
      stage->setStyle("top", px(oy / s))
    } else {
      stage->setStyle("transform", `translate(${px(ox)}, ${px(oy)}) scale(${Float.toString(s)})`)
    }
  }
  let resizeObserver = makeResizeObserver(layout)
  resizeObserver->observe(host)
  layout()

  presets->PresetStore.start
  updatePresetBar()
  pages[0]->Option.forEach(p => status->Status.setIdle(p.hint))

  // The patch's parameters and stored state arrive in one message (asking for each parameter is a
  // round trip through the plugin's web view).
  let disposed = ref(false)
  pc->PatchConnection.requestFullStoredState(state =>
    if !disposed.contents {
      model->ParamModel.loadParameters(state.parameters->Option.getOr([]))
      presets->PresetStore.loadState(state.values->Option.getOr(Dict.make()))
    }
  )

  {
    showPage,
    ctx,
    dispose: () => {
      disposed := true
      resizeObserver->disconnect
      document->offDocumentKeyDown(onShortcut)
      restoreBrowserChrome()
      stopTheme()
      stopSettings()
      settings->Settings.dispose
      hostMenu->HostMenu.dispose
      browser->PresetBrowser.dispose
      model->ParamModel.dispose
      presets->PresetStore.dispose
    },
  }
}

// The view's element, for Index.res: a custom element that lets go of the patch connection when
// it's removed, and offers showPage to the UI preview (view.showPage("fx")).
let elementClass: elementClass = %raw(`
  class extends HTMLElement {
    disconnectedCallback() { this.onDisconnect?.(); }
  }
`)

@set external setOnDisconnect: (element, unit => unit) => unit = "onDisconnect"
@set external setShowPage: (element, string => unit) => unit = "showPage"

let mount = (pc, ~specs, ~pages, ~onDrop=?, ~dropExtensions=?, ~dropText=?, ~buttons=?, ~onReady=?) => {
  if getCustomElement("plugin-view")->Option.isNone {
    defineCustomElement("plugin-view", elementClass)
  }
  let host = document->createElement("plugin-view")
  let view = make(host, pc, ~specs, ~pages, ~onDrop?, ~dropExtensions?, ~dropText?, ~buttons?)
  host->setOnDisconnect(view.dispose)
  host->setShowPage(view.showPage)
  onReady->Option.forEach(f => f(view.ctx))
  host
}
