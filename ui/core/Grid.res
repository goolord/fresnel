// A control grid inside a panel (or any positioned element): controls are placed by
// column and row from an origin.
//
// The layout rules, so that a control never needs a pixel offset:
// - every control fills a cell: Style.controlHeight tall, at the top of its row, and as wide
//   as the columns it spans (less a small gap), so neighbours can never overlap;
// - parameters, lists, switches and grid buttons all have that same footprint;
// - for narrower controls, make a grid with narrower columns (~cw) and give wider controls a
//   span, rather than offsetting them;
// - a cell that is already taken is reported in the console when a second control lands on it.

let columnWidth = 87. // grid column width
let rowHeight = Style.controlHeight + Style.controlGap // grid row height
let padX = 5.
let padTop = 25. // below a panel's title or tab strip
let padBottom = 6.
let gap = 6.
let columnGap = 4. // between the controls of neighbouring columns

// The panel height that fits rows of controls below the title.
let panelHeight = rows => padTop + Int.toFloat(rows) * rowHeight + padBottom
// The height of a panel without a title that fits rows of controls.
let bareHeight = rows => Int.toFloat(rows) * rowHeight + 2. * padBottom - Style.controlGap

// The column width at which this many columns fill a panel this wide (borders included),
// with the same margin left and right.
let fitColumns = (panelWidth, cols) => (panelWidth - 2. - 2. * padX + columnGap) / Int.toFloat(cols)

type t = {
  ctx: Ctx.t,
  el: Dom.element,
  ox: float,
  oy: float,
  cw: float,
  // the cells taken so far, "column,row"
  taken: Set.t<string>,
}

let make = (ctx, el, ~x=padX, ~y=padTop, ~cw=columnWidth) => {
  ctx,
  el,
  ox: x,
  oy: y,
  cw,
  taken: Set.make(),
}

// The left edge of column c's cell (a pixel left of its control, for older call sites) and
// the top of row r.
let cx = (g, c) => g.ox + Int.toFloat(c) * g.cw - 1.
let cy = (g, r) => g.oy + Int.toFloat(r) * rowHeight

// controls keep a few pixels apart, so that each label reads with its own control
let controlWidth = (g, span) => Int.toFloat(span) * g.cw - columnGap

// The box a control spanning these cells fills.
let cell = (g, c, r, ~span=1, ~rows=1): Web.box => {
  x: g.ox + Int.toFloat(c) * g.cw,
  y: cy(g, r),
  w: controlWidth(g, span),
  h: Int.toFloat(rows) * rowHeight - Style.controlGap,
}

// Marks the cells as taken, and warns when one already was.
let claim = (g, c, r, ~span=1, ~rows=1, what) =>
  for i in c to c + span - 1 {
    for j in r to r + rows - 1 {
      let key = `${Int.toString(i)},${Int.toString(j)}`
      if g.taken->Set.has(key) {
        Console.warn(`Grid: ${what} overlaps another control at column ${Int.toString(i)}, row ${Int.toString(j)}`)
      }
      g.taken->Set.add(key)
    }
  }

// Claims cells for `what`, and calls f with the box a control spanning them fills.
let at = (g, c, r, ~span=1, ~rows=1, what, f) => {
  g->claim(c, r, ~span, ~rows, what)
  f(g->cell(c, r, ~span, ~rows))
}

let param = (g, id, c, r, label, ~span=1) =>
  g->at(c, r, ~span, id, b => Controls.param(g.ctx, g.el, id, ~x=b.x, ~y=b.y, ~w=b.w, ~label))

let choice = (g, id, c, r, label, ~span=1) =>
  g->at(c, r, ~span, id, b => Controls.choice(g.ctx, g.el, id, ~x=b.x, ~y=b.y, ~w=b.w, ~label))

let toggle = (g, id, c, r, label, ~span=1) =>
  g->at(c, r, ~span, id, b => Controls.toggle(g.ctx, g.el, id, ~x=b.x, ~y=b.y, ~w=b.w, ~label))

// The control a parameter's kind calls for: a switch for on/off, a list for other lists, a row
// for numbers.
let auto = (g, id, c, r, label, ~span=1) =>
  switch g.ctx.model->ParamModel.def(id) {
  | {names: Some(["off", "on"])} => toggle(g, id, c, r, label, ~span)
  | {names: Some(_)} => choice(g, id, c, r, label, ~span)
  | _ => param(g, id, c, r, label, ~span)
  }

// A rotary knob filling its cells (three rows tall by default, its dial as big as fits).
let knob = (g, id, c, r, label, ~span=1, ~rows=3) =>
  g->at(c, r, ~span, ~rows, id, b =>
    Controls.knob(g.ctx, g.el, id, ~x=b.x, ~y=b.y, ~size=Math.min(b.w, b.h - 30.), ~w=b.w, ~label)
  )

// A button filling its cells.
let button = (g, text, c, r, ~span=1, ~icon=?, ~status=?, onClick) =>
  g->at(c, r, ~span, text, b =>
    Controls.button(g.ctx, g.el, text, ~x=b.x, ~y=b.y, ~w=b.w, ~h=b.h, ~cls="gc", ~icon?, ~status?, onClick)->ignore
  )

// A note (wrapped, faint text) filling a span of cells.
let note = (g, text, c, r, ~span=1, ~rows=1) =>
  g->at(c, r, ~span, ~rows, "a note", b =>
    Web.el("div", ~cls="note wrap", ~text, ~parent=g.el)->Web.placeBox({...b, x: b.x + 2.})
  )
