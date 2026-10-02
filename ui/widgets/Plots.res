// The SVG helpers the plots and graphical editors share: an SVG placed in design pixels, its
// background, lines, paths from points, and curves traced finely enough to stay smooth.

open! Web

let svg = (parent, box) => {
  let s = document->createElementNS(svgNamespace, "svg")
  s->setAttribute("class", Str("plot"))
  s->setAttribute("width", Num(box.w))
  s->setAttribute("height", Num(box.h))
  s->setAttribute("viewBox", Str(`0 0 ${Float.toString(box.w)} ${Float.toString(box.h)}`))
  s->placeBox(box)->ignore
  parent->appendChild(s)
  s
}

let background = (s, box) =>
  s
  ->svgEl(
    "rect",
    [
      ("class", Str("bg")),
      ("x", Num(0.5)),
      ("y", Num(0.5)),
      ("width", Num(box.w - 1.)),
      ("height", Num(box.h - 1.)),
    ],
  )
  ->ignore

// A grid or axis line.
let line = (parent, ~cls="axis", x1, y1, x2, y2) =>
  parent->svgEl(
    "line",
    [("class", Str(cls)), ("x1", Num(x1)), ("y1", Num(y1)), ("x2", Num(x2)), ("y2", Num(y2))],
  )

let pathFrom = points =>
  points
  ->Array.mapWithIndex(((x, y), i) =>
    (i == 0 ? "M" : "L") ++ Float.toFixed(x, ~digits=2) ++ " " ++ Float.toFixed(y, ~digits=2)
  )
  ->Array.join("")

// Adds the curve t => (x, y) for t in (0, 1] to `points`, which already hold its start.
// `steps` even pieces are halved until the curve strays less than a tenth of a pixel from
// each straight line, so that steep bends stay smooth however far a curve is dragged.
let trace = (points, at: float => (float, float), ~steps=16) => {
  let rec piece = (t0: float, p0: (float, float), t1: float, p1: (float, float), depth) => {
    let ((x0, y0), (x1, y1)) = (p0, p1)
    let t = (t0 + t1) / 2.
    let (x, y) as p = at(t)
    // the middle's distance from the straight line
    let (dx, dy) = (x1 - x0, y1 - y0)
    let length2 = dx * dx + dy * dy
    let u = length2 > 0. ? Math.max(0., Math.min(1., ((x - x0) * dx + (y - y0) * dy) / length2)) : 0.
    let (ex, ey) = (x - x0 - u * dx, y - y0 - u * dy)
    if depth < 10 && ex * ex + ey * ey > 0.01 {
      piece(t0, p0, t, p, depth + 1)
      piece(t, p, t1, p1, depth + 1)
    } else {
      points->Array.push(p1)
    }
  }
  let last = ref((0., at(0.)))
  for k in 1 to steps {
    let (t0, p0) = last.contents
    let t1 = Int.toFloat(k) / Int.toFloat(steps)
    let p1 = at(t1)
    piece(t0, p0, t1, p1, 0)
    last := (t1, p1)
  }
}
