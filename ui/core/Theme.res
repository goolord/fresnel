// The design language as data: every colour, font and shape the interface is drawn with. Style.res
// writes the CSS from these as custom properties (var(--ink), var(--radius)...), and the canvases
// read them through CanvasStyle, so a theme changes everything at once, and the view can switch
// themes while it runs (the settings dialog offers the plugin's themes).
//
// To restyle a plugin, edit a theme here or add one (ui/plugin/App.res says which themes the plugin
// offers and which comes first). Colours are "r, g, b" so that they can be used at any alpha.

type t = {
  // the name the settings dialog shows
  name: string,
  // behind the panels
  ground: string,
  // panels, and their lighter hover/raised colour
  panel: string,
  panelHi: string,
  // borders
  edge: string,
  // text, from strongest to faintest
  ink: string,
  inkSoft: string,
  inkFaint: string,
  // everything that carries a value: tracks, curves, the selected tab
  signal: string,
  // fields, menus and graph backgrounds
  paper: string,
  // modulation, and second curves
  mod: string,
  // a good state, or a gain that goes up
  good: string,
  // what every control sits on, so that it reads as something to grab (alpha over the panel)
  tileAlpha: float,
  tileEdgeAlpha: float,
  // text on the signal colour (the selected tab, a lit button)
  onSignal: string,
  // fonts: the layouts are drawn for a narrow face (Bahnschrift, DIN); a wide one crowds the
  // value fields, so pick a condensed one or a smaller size
  font: string,
  fontStretch: string,
  titleWeight: int,
  // corner radii: panels, and controls
  radius: float,
  controlRadius: float,
  // the drop shadow of menus and dialogs: an offset, and how far it blurs (0: a hard shadow)
  shadowOffset: float,
  shadowBlur: float,
  shadowAlpha: float,
  // how labels and panel titles are set: "none" (as written: lowercase), "uppercase", "capitalize"
  labelCase: string,
  titleCase: string,
}

// Khaki panels, lowercase labels, bold lowercase block titles, and one blue ink for everything
// that carries a value.
let oat = {
  name: "oat",
  ground: "151, 133, 82",
  panel: "185, 170, 123",
  panelHi: "201, 188, 146",
  edge: "111, 95, 54",
  ink: "31, 26, 14",
  inkSoft: "76, 65, 39",
  inkFaint: "122, 108, 69",
  signal: "28, 60, 115",
  paper: "236, 227, 196",
  mod: "163, 80, 28",
  good: "63, 122, 58",
  tileAlpha: 0.32,
  tileEdgeAlpha: 0.4,
  onSignal: "236, 227, 196",
  font: `Bahnschrift, "DIN Alternate", "DIN 2014", "Barlow", "Arial Narrow", sans-serif`,
  fontStretch: "semi-condensed",
  titleWeight: 700,
  radius: 3.,
  controlRadius: 2.,
  shadowOffset: 3.,
  shadowBlur: 0.,
  shadowAlpha: 0.35,
  labelCase: "none",
  titleCase: "none",
}

// Dark grey panels with an amber signal.
let night = {
  name: "night",
  ground: "24, 25, 28",
  panel: "38, 40, 45",
  panelHi: "52, 55, 62",
  edge: "70, 74, 84",
  ink: "226, 228, 232",
  inkSoft: "170, 174, 184",
  inkFaint: "116, 121, 133",
  signal: "240, 166, 60",
  paper: "28, 29, 33",
  mod: "96, 176, 230",
  good: "120, 200, 120",
  tileAlpha: 0.06,
  tileEdgeAlpha: 0.12,
  onSignal: "24, 25, 28",
  font: `Bahnschrift, "DIN Alternate", "Barlow Semi Condensed", "Roboto Condensed", "Arial Narrow", sans-serif`,
  fontStretch: "semi-condensed",
  titleWeight: 600,
  radius: 6.,
  controlRadius: 4.,
  shadowOffset: 4.,
  shadowBlur: 14.,
  shadowAlpha: 0.5,
  labelCase: "none",
  titleCase: "capitalize",
}

// White paper, black ink and a red signal: a printed panel.
let paper = {
  name: "paper",
  ground: "214, 212, 206",
  panel: "244, 243, 239",
  panelHi: "255, 255, 255",
  edge: "150, 147, 140",
  ink: "20, 20, 20",
  inkSoft: "70, 70, 70",
  inkFaint: "128, 126, 120",
  signal: "200, 46, 38",
  paper: "255, 255, 255",
  mod: "40, 90, 200",
  good: "40, 130, 60",
  tileAlpha: 0.5,
  tileEdgeAlpha: 0.25,
  onSignal: "255, 255, 255",
  font: `"IBM Plex Sans Condensed", "Roboto Condensed", "Arial Narrow", sans-serif`,
  fontStretch: "condensed",
  titleWeight: 700,
  radius: 0.,
  controlRadius: 0.,
  shadowOffset: 2.,
  shadowBlur: 0.,
  shadowAlpha: 0.25,
  labelCase: "none",
  titleCase: "uppercase",
}

let rgb = c => `rgb(${c})`
let rgba = (c, alpha) => `rgba(${c}, ${Float.toString(alpha)})`

// The theme as CSS custom properties, for the view's root (Style.css uses only these).
let properties = t => [
  ("--ground", rgb(t.ground)),
  ("--panel", rgb(t.panel)),
  ("--panel-hi", rgb(t.panelHi)),
  ("--edge", rgb(t.edge)),
  ("--ink", rgb(t.ink)),
  ("--ink-soft", rgb(t.inkSoft)),
  ("--ink-faint", rgb(t.inkFaint)),
  ("--signal", rgb(t.signal)),
  ("--signal-soft", rgba(t.signal, 0.22)),
  ("--paper", rgb(t.paper)),
  ("--mod", rgb(t.mod)),
  ("--good", rgb(t.good)),
  ("--on-signal", rgb(t.onSignal)),
  ("--tile", rgba(t.paper, t.tileAlpha)),
  ("--tile-edge", rgba(t.edge, t.tileEdgeAlpha)),
  // for colours at other alphas: rgba(var(--ink-rgb), 0.2)
  ("--ink-rgb", t.ink),
  ("--edge-rgb", t.edge),
  ("--signal-rgb", t.signal),
  ("--paper-rgb", t.paper),
  ("--font", t.font),
  ("--font-stretch", t.fontStretch),
  ("--title-weight", Int.toString(t.titleWeight)),
  ("--radius", Web.px(t.radius)),
  ("--radius-sm", Web.px(t.controlRadius)),
  (
    "--shadow",
    `${Web.px(t.shadowOffset)} ${Web.px(t.shadowOffset)} ${Web.px(t.shadowBlur)} ${rgba(t.ink, t.shadowAlpha)}`,
  ),
  ("--label-case", t.labelCase),
  ("--title-case", t.titleCase),
]

// The theme in use, which the canvases draw with; App sets it, and the settings dialog changes it.
let current = ref(oat)

let listeners: ref<array<t => unit>> = ref([])

// Calls fn with every new theme; returns a function that stops it.
let onChange = fn => {
  let wrapped = t => fn(t)
  listeners := [...listeners.contents, wrapped]
  () => listeners := listeners.contents->Array.filter(f => f !== wrapped)
}

let set = t => {
  current := t
  listeners.contents->Array.forEach(fn => fn(t))
}
