// What the drawing canvases share: a canvas at twice the design resolution, and the paper, grid and
// ink they are drawn in, from the current theme (a canvas redraws itself when the theme changes,
// see onThemeChange).

open! Web

let theme = () => Theme.current.contents

let ink = () => Theme.rgb(theme().signal)
// the ink, see-through
let tint = alpha => Theme.rgba(theme().signal, alpha)
// grid lines and other marks in the text colour
let shade = alpha => Theme.rgba(theme().ink, alpha)

// A canvas filling a box, at twice its resolution.
let make = (parent, b: box) => {
  let c = el("canvas", ~cls="draw", ~parent)->placeBox(b)
  c->setCanvasWidth(b.w * 2.)
  c->setCanvasHeight(b.h * 2.)
  c
}

// Clears the canvas to the paper, and returns its size.
let paper = (canvas, g) => {
  open Context2d
  let (w, h) = (canvas->canvasWidth, canvas->canvasHeight)
  g->clearRect(0., 0., w, h)
  g->setFillStyle(Theme.rgba(theme().paper, 0.45))
  g->fillRect(0., 0., w, h)
  (w, h)
}

// One-pixel grid lines across the canvas, on the pixel grid.
let line = (g, (x1, y1), (x2, y2), colour) => {
  open Context2d
  g->setStrokeStyle(colour)
  g->setLineWidth(1.)
  g->beginPath
  g->moveTo(x1, y1)
  g->lineTo(x2, y2)
  g->stroke
}
let snap = v => Math.round(v) + 0.5
let hline = (g, w, y, colour) => line(g, (0., snap(y)), (w, snap(y)), colour)
let vline = (g, h, x, colour) => line(g, (snap(x), 0.), (snap(x), h), colour)

let border = (g, w, h) => {
  open Context2d
  g->setStrokeStyle(Theme.rgb(theme().edge))
  g->setLineWidth(2.)
  g->strokeRect(1., 1., w - 2., h - 2.)
}

// Redraws with the new colours whenever the theme changes.
let onThemeChange = redraw => Theme.onChange(_ => redraw())->ignore
