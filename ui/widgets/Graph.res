// What the graphs share (the envelopes, the LFO plot, the meter...): an SVG area, points to drag
// (each bound to parameters), axis ticks, frequency and level scales, and redraws that wait for the
// next frame and skip hidden tabs.

open! Web

let clamp = (x: float, lo, hi) => Math.max(lo, Math.min(hi, x))
// a gain in dB, down to -180
let db = (x: float) => x <= 1e-9 ? -180. : 20. * Math.log10(x)

// A point to drag. Points with the same key light up together.
type handle = {
  dot: element,
  hit: element,
  key: string,
  hot: bool,
  mutable x: float,
  mutable y: float,
}

type t = {
  ctx: Ctx.t,
  root: element,
  svg: element,
  w: float,
  h: float,
  // what is drawn under the points; the points; their hit areas, above every drawing, with the
  // label beside the point in focus
  under: element,
  layer: element,
  hits: element,
  readout: element,
  // the status line while the pointer is over the graph
  hint: option<string>,
  handles: array<handle>,
  // the key of the point under the pointer
  mutable focus: option<string>,
  mutable dragging: bool,
  // redraws what the point under the pointer changes
  mutable redraw: unit => unit,
}

let group = (parent, ~cls="") => svgEl(parent, "g", cls == "" ? [] : [("class", Str(cls))])

let make = (ctx: Ctx.t, parent, box: box, ~hint=?) => {
  let root = el("div", ~cls="ed", ~parent)->placeBox(box)
  let area = {x: 0., y: 0., w: box.w, h: box.h}
  let svg = Plots.svg(root, area)
  Plots.background(svg, area)
  svg->suppressContextMenu
  let under = group(svg)
  let layer = group(svg)
  let hits = group(svg)
  let readout = svgEl(hits, "text", [("class", Str("readout"))])
  let g = {
    ctx,
    root,
    svg,
    w: box.w,
    h: box.h,
    under,
    layer,
    hits,
    readout,
    hint,
    handles: [],
    focus: None,
    dragging: false,
    redraw: () => (),
  }
  hint->Option.forEach(hint => {
    svg->onMouse(#mouseenter, _ => ctx.status->Status.show(hint))
    svg->onMouse(#mouseleave, _ =>
      if !g.dragging {
        ctx.status->Status.clear
      }
    )
  })
  g
}

// A graph filling a panel, under its title.
let inPanel = (ctx, p: Panel.t, ~hint=?) =>
  make(ctx, p.el, {x: 8., y: 25., w: p.w - 18., h: p.h - 35.}, ~hint?)

let line = (parent, ~cls, x1, y1, x2, y2) => Plots.line(parent, ~cls, x1, y1, x2, y2)->ignore

let text = (parent, ~cls="tick", ~anchor="start", x, y, s) =>
  svgEl(
    parent,
    "text",
    [("class", Str(cls)), ("x", Num(x)), ("y", Num(y)), ("text-anchor", Str(anchor))],
  )->setTextContent(s)

let path = (parent, ~cls) => svgEl(parent, "path", [("class", Str(cls))])

let setPath = (e, d) => e->setAttribute("d", Str(d))

// Whether the graph is on screen (its tab is shown).
let shown = g => g.root->offsetParent->Option.isSome

// A redraw at the next frame, once however often it is asked for; nothing while hidden (the
// page calls `now` when the tab is shown).
type redraw = {request: unit => unit, now: unit => unit}

let redraw = (g, draw) => {
  let pending = ref(false)
  let now = () => {
    pending := false
    draw()
  }
  {
    request: () =>
      if !pending.contents && shown(g) {
        pending := true
        requestAnimationFrame(_ => if pending.contents {
          now()
        })
      },
    now,
  }
}

// Draws every frame (or every other one) while the graph is on screen, once the function this
// returns starts it; draw gets the frame's time in ms.
let animate = (g, ~everyOther=false, draw) => {
  let running = ref(false)
  let odd = ref(false)
  let rec frame = now =>
    if shown(g) {
      odd := !odd.contents
      if odd.contents || !everyOther {
        draw(now)
      }
      requestAnimationFrame(frame)
    } else {
      running := false
    }
  () =>
    if !running.contents {
      running := true
      requestAnimationFrame(frame)
    }
}

// Calls fn whenever one of these parameters changes.
let listen = (g, ids, fn) => g.ctx.model->ParamModel.listenEach(ids, fn)

let get = (g, id) => g.ctx.model->ParamModel.get(id)
let set = (g, id, x) => g.ctx.model->ParamModel.set(id, x)
let def = (g, id) => g.ctx.model->ParamModel.def(id)

let short = (g, id) => g.ctx.model->ParamModel.shortText(id)

//==============================================================================
// Points to drag

// Where a dragged point would be: where it was when the drag started, moved by dx and dy.
type move = {x: float, y: float, dx: float, dy: float}

// A point, drawn in the graph's layer with its hit area in its hits. Dragging calls drag with
// where it would be, in graph pixels (moved a tenth as far with shift), between gestures on its
// parameters, and shows them in the status line (unless statusOnDrag is false); right-click puts
// them back to their defaults; the wheel scrolls the parameter `wheel`. The pointer over it
// lights it up (unless hot is false) with the points that share its key, shows its parameters
// (or what `hover` shows; the hint when it leaves) and redraws.
let handle = (
  g,
  ~cls="node",
  ~r=6.,
  ~cursor="move",
  ~ids: array<string>,
  ~key=ids->Array.join(" "),
  ~hot=true,
  ~statusOnDrag=true,
  ~drag: move => unit,
  ~start=() => (),
  ~finish=() => (),
  ~wheel: option<string>=?,
  ~rightClick: option<unit => unit>=?,
  ~hover: option<bool => unit>=?,
) => {
  let dot = svgEl(g.layer, "circle", [("class", Str(cls)), ("r", Num(r))])
  let hit = svgEl(
    g.hits,
    "circle",
    [("class", Str("hit")), ("r", Num(r + 5.)), ("style", Str("cursor:" ++ cursor))],
  )
  let h = {dot, hit, key, hot, x: 0., y: 0.}
  g.handles->Array.push(h)
  let model = g.ctx.model
  hit->onPointer(#pointerdown, ev => {
    ev->preventDefault
    // not a press on the graph behind it too
    ev->stopPropagation
    switch ev->button {
    | 0 =>
      ids->Array.forEach(id => model->ParamModel.beginGesture(id))
      g.dragging = true
      start()
      let k = g.w / (g.svg->getBoundingClientRect).width
      let (x, y) = (h.x, h.y)
      let last = ref((ev->clientX, ev->clientY))
      let moved = ref((0., 0.))
      hit->Controls.capturePointer(
        ev,
        ~onMove=mv => {
          let (lx, ly) = last.contents
          last := (mv->clientX, mv->clientY)
          let f = mv->shiftKey ? 0.1 * k : k
          let (mx, my) = moved.contents
          let (dx, dy) = (mx + (mv->clientX - lx) * f, my + (mv->clientY - ly) * f)
          moved := (dx, dy)
          drag({x: x + dx, y: y + dy, dx, dy})
          if statusOnDrag {
            g.ctx.status->Status.show(model->ParamModel.statusText(ids))
          }
        },
        ~onUp=() => {
          ids->Array.forEach(id => model->ParamModel.endGesture(id))
          g.dragging = false
          finish()
        },
      )
    | 2 =>
      switch rightClick {
      | Some(fn) => fn()
      | None => ids->Array.forEach(id => model->ParamModel.gestureSet(id, def(g, id).init))
      }
    | _ => ()
    }
  })
  wheel->Option.forEach(id => hit->onWheel(ev => Controls.wheelParam(model, id, ev)))
  let pointed = on => {
    g.focus = on ? Some(key) : None
    g.handles->Array.forEach(o =>
      if o.hot {
        o.dot->toggleClass("hot", g.focus == Some(o.key))
      }
    )
    switch hover {
    | Some(fn) => fn(on)
    | None if on => g.ctx.status->Status.show(model->ParamModel.statusText(ids))
    | None =>
      switch g.hint {
      | Some(hint) => g.ctx.status->Status.show(hint)
      | None => g.ctx.status->Status.clear
      }
    }
    g.redraw()
  }
  hit->onMouse(#mouseenter, _ => pointed(true))
  hit->onMouse(#mouseleave, _ => pointed(false))
  h
}

let place = (h: handle, x, y) => {
  h.x = x
  h.y = y
  [h.dot, h.hit]->Array.forEach(e => {
    e->setAttribute("cx", Num(x))
    e->setAttribute("cy", Num(y))
  })
}

let show = (h: handle, on) => [h.dot, h.hit]->Array.forEach(e => e->setStyle("display", on ? "" : "none"))

// The label beside a point (x, y), kept inside the graph: dx to its right on the left of the
// graph (left of it on the right), above it by `above`, or below it by `below` when it is within
// nearTop of the top.
let readout = (g, ~x, ~y, ~dx=12., ~above=10., ~below=22., ~nearTop=30., s) => {
  let leftHalf = x < g.w * 0.6
  g.readout->setTextContent(s)
  g.readout->setAttribute("x", Num(leftHalf ? x + dx : x - dx))
  g.readout->setAttribute("y", Num(y < nearTop ? y + below : y - above))
  g.readout->setAttribute("text-anchor", Str(leftHalf ? "start" : "end"))
}

let hideReadout = g => g.readout->setTextContent("")

//==============================================================================
// Axes

// A round step that puts about `count` ticks across `span`.
let niceStep = (span: float, count: float) => {
  let raw = span / count
  let p = Math.pow(10., ~exp=Math.floor(Math.log10(raw)))
  let m = raw / p
  p * (m < 1.5 ? 1. : m < 3.5 ? 2. : m < 7.5 ? 5. : 10.)
}

// Calls f at from, from + step, ... while it is up to until.
let ticks = (~from=0., ~until, ~step, f) => {
  let v = ref(from)
  while v.contents <= until {
    f(v.contents)
    v := v.contents + step
  }
}

// A frequency axis tick: "500", "2k".
let hzTick = (hz: float) => hz >= 1000. ? `${Float.toString(hz / 1000.)}k` : Float.toString(hz)

let gainDb = (x: float) => x <= 0. ? -120. : 20. * Math.log10(x)

// A log scale from lo at `left` to hi at `right`: a value's x, and the value at an x (both held
// to the ends).
let logX = (~lo: float, ~hi: float, ~left: float, ~right: float, v: float) =>
  left + Math.log(clamp(v, lo, hi) / lo) / Math.log(hi / lo) * (right - left)
let logAt = (~lo: float, ~hi: float, ~left: float, ~right: float, x: float) =>
  lo * Math.pow(hi / lo, ~exp=clamp((x - left) / (right - left), 0., 1.))
let logScale = (~lo, ~hi, ~left, ~right) => (
  logX(~lo, ~hi, ~left, ~right, ...),
  logAt(~lo, ~hi, ~left, ~right, ...),
)

//==============================================================================
// Plots: frequency (20 Hz .. 20 kHz on a log scale) or time across, drawn in a layer between
// these edges

type plot = {
  layer: element,
  left: float,
  right: float,
  top: float,
  bottom: float,
}

let xOfHz = (p, hz) => logX(~lo=20., ~hi=20000., ~left=p.left, ~right=p.right, hz)
let hzAt = (p, x) => logAt(~lo=20., ~hi=20000., ~left=p.left, ~right=p.right, x)
let yOf = (p, v: float, lo: float, hi: float) =>
  p.bottom - (clamp(v, lo, hi) - lo) / (hi - lo) * (p.bottom - p.top)

let frequencies = [50., 100., 200., 500., 1000., 2000., 5000., 10000.]

// Lines up at these frequencies, labelled at labelY.
let frequencyLines = (p, ~labelY=p.bottom + 12., ~labels=true, fs) =>
  fs->Array.forEach(f => {
    let x = xOfHz(p, f)
    line(p.layer, ~cls="grid", x, p.top, x, p.bottom)
    if labels {
      text(p.layer, ~anchor="middle", x, labelY, hzTick(f))
    }
  })

// Lines across at these levels (dB from lo to hi), labelled on the left; 0 dB is the axis.
let levelLines = (p, ~lo, ~hi, levels) =>
  levels->Array.forEach(v => {
    let y = yOf(p, v, lo, hi)
    line(p.layer, ~cls=v == 0. ? "axis" : "grid", p.left, y, p.right, y)
    text(p.layer, ~anchor="end", p.left - 4., y + 4., Float.toString(v))
  })

// The frequency grid, and levels every step from lo to hi.
let frequencyGrid = (p, ~lo, ~hi, ~step) => {
  frequencyLines(p, frequencies)
  let levels = []
  ticks(~from=lo, ~until=hi, ~step, v => levels->Array.push(v))
  levelLines(p, ~lo, ~hi, levels)
}

// A response curve: dB at each of `steps` frequencies across.
let response = (p, ~cls="curve", ~lo, ~hi, ~steps=240, magnitude: float => float) => {
  let points = Array.fromInitializer(~length=steps + 1, k => {
    let x = p.left + Int.toFloat(k) / Int.toFloat(steps) * (p.right - p.left)
    (x, yOf(p, db(magnitude(hzAt(p, x))), lo, hi))
  })
  path(p.layer, ~cls)->setPath(Plots.pathFrom(points))
}

let note = (p, ~x=?, ~y=?, ~anchor="start", s) =>
  text(p.layer, ~cls="tick", ~anchor, x->Option.getOr(p.left + 6.), y->Option.getOr(p.top + 14.), s)
