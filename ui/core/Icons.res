// Small inline icons for list values, drawn as strokes in the current text colour.
//
// An icon is drawn on a grid 16 units tall. A list parameter shows icons when the plugin registers
// how to find the icon of each of its values (register, in App.res); a value without one simply
// has none.

open! Web

type mark =
  // a stroked path
  | Line(string)
  // a dashed stroked path
  | Dash(string)
  // a filled path
  | Fill(string)
  // a filled dot
  | Dot(float, float, float)
  // a small label (a digit)
  | Text(float, float, string)

// (mirrored: drawn right to left)
type icon = {width: float, marks: array<mark>, mirrored?: bool}

// The icon as an <svg>, 1em tall by default (CSS sets the size).
let render = (icon, ~cls="ic") => {
  let s = document->createElementNS(svgNamespace, "svg")
  s->setAttribute("class", Str(cls))
  s->setAttribute("viewBox", Str(`0 0 ${Float.toString(icon.width)} 16`))
  s->setAttribute("width", Num(icon.width))
  s->setAttribute("height", Num(16.))
  let marks = s->svgEl(
    "g",
    icon.mirrored == Some(true)
      ? [("transform", Str(`matrix(-1 0 0 1 ${Float.toString(icon.width)} 0)`))]
      : [],
  )
  icon.marks->Array.forEach(mark =>
    switch mark {
    | Line(d) => marks->svgEl("path", [("d", Str(d))])->ignore
    | Dash(d) => marks->svgEl("path", [("d", Str(d)), ("class", Str("dash"))])->ignore
    | Fill(d) => marks->svgEl("path", [("d", Str(d)), ("class", Str("f"))])->ignore
    | Dot(x, y, r) =>
      marks->svgEl("circle", [("cx", Num(x)), ("cy", Num(y)), ("r", Num(r)), ("class", Str("f"))])->ignore
    | Text(x, y, text) =>
      let t = marks->svgEl("text", [("x", Num(x)), ("y", Num(y))])
      t->setTextContent(text)
    }
  )
  s
}

//==============================================================================
// which parameters show icons

// How a parameter finds the icon of a value from its index and its lower-case name.
let registry: Map.t<string, (int, string) => option<icon>> = Map.make()

let register = (id, find) => registry->Map.set(id, find)

let byIndex = icons => (index, _) => icons[index]

// Whether any value of the parameter has an icon.
let has = id => registry->Map.has(id)

// The icon for value `index` (named `name`) of a list parameter, in its wrapper.
let forValue = (id, index, name) =>
  registry
  ->Map.get(id)
  ->Option.flatMap(find => find(index, String.toLowerCase(name)))
  ->Option.map(icon => {
    let wrap = el("span", ~cls="icw")
    wrap->appendChild(render(icon))
    wrap
  })
