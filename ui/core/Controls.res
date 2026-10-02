// Panel controls. Every control is bound to one parameter by its id (the endpoint's name, see
// Param.res), and behaves the same way: drag (shift and ctrl for finer steps) or scroll to change
// it, double-click or Enter to type a value, right-click to reset it, a middle click for the
// middle of its range, arrow keys when focused, and a double right-click for the host's menu.

open! Web

let dragPixels = 220. // pixels of vertical travel for the full range
let fineShift = 0.1
let fineCtrl = 0.25

let clamp01 = x => Float.clamp(x, ~min=0., ~max=1.)

let block = (parent, title, ~x, ~y, ~w, ~h) => {
  let e = el("div", ~cls="blk", ~parent)->place(x, y, ~w, ~h)
  if title != "" {
    el("div", ~cls="ttl", ~text=title, ~parent=e)->ignore
  }
  e
}

// A control: its parameter, and the status text it shows while hovered or dragged
type control = {
  ctx: Ctx.t,
  id: string,
  def: Param.t,
  status: Status.live,
}

let current = c => c.ctx.model->ParamModel.get(c.id)
let gestureSet = (c, x) => c.ctx.model->ParamModel.gestureSet(c.id, x)
let refreshStatus = c => c.status.refresh()

// A double right-click opens the host's menu for the parameter (see HostMenu). Hook it before
// the control's own pointer handlers.
let hookHostMenu = (c, e) => c.ctx.hostMenu->HostMenu.attach(c.ctx.model, e, c.id)

// A control's element: focusable, with its label (after an on/off box, with ~box), showing the
// parameter's status text while hovered, and the host's menu on a double right-click.
let frame = (ctx: Ctx.t, parent, id, ~cls, ~x, ~y, ~w=?, ~label=?, ~labelCls=?, ~box=false) => {
  let e = el("div", ~cls, ~parent)->place(x, y, ~w?)
  let def = ctx.model->ParamModel.def(id)
  let c = {ctx, id, def, status: ctx.status->Status.live(e, () => def.longText(ctx.model->ParamModel.get(id)))}
  e->setTabIndex(0)
  if box {
    el("b", ~parent=e)->ignore
  }
  el("span", ~cls=?labelCls, ~text=label->Option.getOr(c.def.name), ~parent=e)->ignore
  hookHostMenu(c, e)
  (c, e)
}

// Runs update now and whenever the control's parameter changes.
let bind = (c, update) => {
  c.ctx.model->ParamModel.listen(c.id, update)
  update()
}

// Calls onMove for every move of a captured pointer, and onUp once it is released.
let capturePointer = (e, ev, ~onMove, ~onUp) => {
  e->setPointerCapture(ev->pointerId)
  let rec up = _ => {
    e->offPointer(#pointermove, onMove)
    e->offPointer(#pointerup, up)
    e->offPointer(#pointercancel, up)
    onUp()
  }
  e->onPointer(#pointermove, onMove)
  e->onPointer(#pointerup, up)
  e->onPointer(#pointercancel, up)
}

// Captures the pointer, and calls onMove with how far each move went (right and down, in
// design pixels), and onUp once it is released.
let dragBy = (ctx: Ctx.t, e, ev, ~onMove, ~onUp) => {
  let scale = ctx.scale()
  let last = ref((ev->clientX, ev->clientY))
  e->capturePointer(
    ev,
    ~onMove=mv => {
      let (lastX, lastY) = last.contents
      last := (mv->clientX, mv->clientY)
      onMove((mv->clientX - lastX) / scale, (mv->clientY - lastY) / scale, mv)
    },
    ~onUp,
  )
}

// Scrolling over a parameter: a hundredth of its knob a notch, shift for a tenth of that.
let wheelParam = (model, id, ev) => {
  ev->preventDefault
  let def = model->ParamModel.def(id)
  let d = (ev->deltaY < 0. ? 1. : -1.) / 100.
  let d = ev->shiftKey ? d * fineShift : d
  model->ParamModel.gestureSet(id, def.fromNorm(clamp01(def.toNorm(model->ParamModel.get(id)) + d)))
}

// Replaces e with a text field until Enter, Escape or blur; commit gets the text on Enter or blur.
// The field goes into e's parent, or over e inside ~within.
let editInPlace = (e, text, ~commit, ~maxLength=?, ~within=?) => {
  let input = el("input", ~cls="entry", ~parent=?within->Option.orElse(e->parentElement))
  let (x, y) = switch within {
  | Some(ancestor) => e->offsetWithin(ancestor)
  | None => (e->offsetLeft, e->offsetTop)
  }
  input->place(x, y, ~w=e->offsetWidth, ~h=e->offsetHeight)->ignore
  maxLength->Option.forEach(n => input->setMaxLength(n))
  input->setValue(text)
  input->select
  input->focus

  let finished = ref(false)
  let finish = ok =>
    if !finished.contents {
      finished := true
      if ok {
        commit(input->value)
      }
      input->remove
      e->focus
    }
  input->onKeyDown(k => {
    k->stopPropagation
    switch k->key {
    | "Enter" => finish(true)
    | "Escape" => finish(false)
    | _ => ()
    }
  })
  input->onEvent(#blur, _ => finish(true))
}

// Modulation, if the plugin has any: the knob range a parameter is swept over, relative to its
// knob position (lo, hi), and a way to hear when that may have changed. The parameter rows show
// it as a bar under their track. App.res sets it; without it, there are no bars.
type modulation = {
  range: (ParamModel.t, string) => option<(float, float)>,
  // whether a parameter can be modulated at all (only those get a bar)
  reaches: string => bool,
  // calls the function whenever the ranges may have changed
  listen: (ParamModel.t, unit => unit) => unit,
}

let modulation: ref<option<modulation>> = ref(None)

let modulationRange = (model, id) => modulation.contents->Option.flatMap(m => m.range(model, id))

// The modulation bars of a model's parameter rows, redrawn together (once a frame) when the
// ranges change: one listener rather than one per row.
let modBars: WeakMap.t<ParamModel.t, array<unit => unit>> = WeakMap.make()

let onModulationChange = (model, refresh) =>
  switch (modBars->WeakMap.get(model), modulation.contents) {
  | (Some(refreshers), _) => refreshers->Array.push(refresh)
  | (None, Some(m)) =>
    let refreshers = [refresh]
    modBars->WeakMap.set(model, refreshers)->ignore
    m.listen(model, perFrame(() => refreshers->Array.forEach(f => f())))
  | (None, None) => ()
  }

// What every value control does with the pointer, the wheel and the keys: drag up (or right) to
// raise the value, shift for a tenth of the speed and ctrl for a quarter; right-click resets it,
// a middle click sets the middle of its range; double-click or Enter types a value; the arrow
// keys step it (shift for fine steps), Delete resets it.
let valueInput = (c, e) => {
  let ctx = c.ctx
  let id = c.id
  let norm = () => c.def.toNorm(current(c))
  let setNorm = n => ctx.model->ParamModel.set(id, c.def.fromNorm(clamp01(n)))
  let edit = () =>
    editInPlace(e, c.def.shortText(current(c)), ~commit=text =>
      switch c.def.parse(text) {
      | Some(x) if Float.isFinite(x) => gestureSet(c, x)
      | _ => ()
      }
    )

  e->onPointer(#pointerdown, ev =>
    switch ev->button {
    | 2 =>
      gestureSet(c, c.def.init)
      ev->preventDefault
    | 1 =>
      gestureSet(c, c.def.fromNorm(0.5))
      ev->preventDefault
    | 0 =>
      ev->preventDefault
      c.status.setDragging(true)
      e->addClass("drag")
      ctx.model->ParamModel.beginGesture(id)

      let n = ref(norm())
      dragBy(
        ctx,
        e,
        ev,
        ~onMove=(dx, dy, mv) => {
          let d = (dx * 0.35 - dy) / dragPixels
          let d = mv->shiftKey ? d * fineShift : d
          let d = mv->commandKey ? d * fineCtrl : d
          n := clamp01(n.contents + d)
          setNorm(n.contents)
        },
        ~onUp=() => {
          c.status.setDragging(false)
          e->removeClass("drag")
          ctx.model->ParamModel.endGesture(id)
        },
      )
      refreshStatus(c)
    | _ => ()
    }
  )
  e->onWheel(ev => wheelParam(ctx.model, id, ev))
  e->onMouse(#dblclick, ev => {
    ev->preventDefault
    edit()
  })
  e->suppressContextMenu
  e->onKeyDown(ev => {
    let step = ev->shiftKey ? 0.001 : 0.01
    switch ev->key {
    | "ArrowUp" | "ArrowRight" =>
      setNorm(norm() + step)
      ev->preventDefault
    | "ArrowDown" | "ArrowLeft" =>
      setNorm(norm() - step)
      ev->preventDefault
    | "Enter" =>
      ev->preventDefault
      edit()
    | "Delete" | "Backspace" => gestureSet(c, c.def.init)
    | _ => ()
    }
  })
}

// A parameter row: label above-left, value right, position track underneath.
let paramControl = (ctx, parent, id, ~x, ~y, ~w=76., ~label=?) => {
  let (c, e) = frame(ctx, parent, id, ~cls="p", ~x, ~y, ~w, ~label?, ~labelCls="l")
  let v = el("span", ~cls="v", ~parent=e)
  let track = el("span", ~cls="t", ~parent=e)
  let fill = el("i", ~parent=track)
  // the range modulation sweeps, for parameters it can reach
  let modBar = modulation.contents->Option.mapOr(false, m => m.reaches(id)) ? Some(el("em", ~parent=track)) : None
  let norm = () => c.def.toNorm(current(c))

  let updateModBar = () =>
    modBar->Option.forEach(bar =>
      switch modulationRange(ctx.model, id) {
      | Some((lo, hi)) =>
        let n = clamp01(norm())
        let (a, b) = (clamp01(n + lo), clamp01(n + hi))
        bar->setStyle("display", "block")
        bar->setStyle("left", Float.toString(a * 100.) ++ "%")
        bar->setStyle("width", Float.toString(Math.max(0.5, (b - a) * 100.)) ++ "%")
      | None => bar->setStyle("display", "none")
      }
    )

  let update = () => {
    let x = current(c)
    v->setTextContent(c.def.shortText(x))
    let n = clamp01(c.def.toNorm(x))
    if c.def.bipolar {
      let (a, b) = (Math.min(n, 0.5), Math.max(n, 0.5))
      fill->setStyle("left", Float.toString(a * 100.) ++ "%")
      fill->setStyle(
        "width",
        b - a < 0.004 ? "1px" : Float.toString(Math.max(1., (b - a) * 100.)) ++ "%",
      )
    } else {
      fill->setStyle("left", "0")
      fill->setStyle("width", Float.toString(n * 100.) ++ "%")
    }
    updateModBar()
    refreshStatus(c)
  }

  valueInput(c, e)
  if modBar != None {
    onModulationChange(ctx.model, updateModBar)
  }
  bind(c, update)
  e
}

let param = (ctx, parent, id, ~x, ~y, ~w=?, ~label=?) =>
  paramControl(ctx, parent, id, ~x, ~y, ~w?, ~label?)->ignore

// A rotary knob: an arc that fills from the bottom left (from the top for a bipolar parameter),
// the value under it and the label above. It behaves like a parameter row; `size` is the knob's
// diameter, and the control is size + 30 tall and w wide (by default as wide as fits its texts).
let knob = (ctx, parent, id, ~x, ~y, ~size=40., ~w=?, ~label=?) => {
  let w = w->Option.getOr(Math.max(size, 56.))
  let (c, e) = frame(ctx, parent, id, ~cls="knob", ~x, ~y, ~w, ~label?, ~labelCls="l")
  e->setStyle("height", px(size + 30.))
  let s = document->createElementNS(svgNamespace, "svg")
  s->setAttribute("class", Str("dial"))
  s->setAttribute("width", Num(size))
  s->setAttribute("height", Num(size))
  s->setAttribute("viewBox", Str("-1 -1 2 2"))
  e->appendChild(s)
  let v = el("span", ~cls="v", ~parent=e)
  // the arc runs 270 degrees, from 225 (bottom left) clockwise to -45 (bottom right)
  let (start, sweep) = (0.75 * Math.Constants.pi, 1.5 * Math.Constants.pi)
  let at = (n, r) => {
    let a = start + n * sweep
    (Math.cos(a) * r, Math.sin(a) * r)
  }
  let arc = (n0, n1, r) => {
    let (x0, y0) = at(n0, r)
    let (x1, y1) = at(n1, r)
    let large = (n1 - n0) * sweep > Math.Constants.pi ? 1 : 0
    let f = Float.toFixed(_, ~digits=4)
    `M${f(x0)} ${f(y0)} A${f(r)} ${f(r)} 0 ${Int.toString(large)} 1 ${f(x1)} ${f(y1)}`
  }
  let r = 0.82
  svgEl(s, "path", [("class", Str("track")), ("d", Str(arc(0., 1., r)))])->ignore
  let fill = svgEl(s, "path", [("class", Str("fill"))])
  svgEl(s, "circle", [("class", Str("cap")), ("r", Num(0.56))])->ignore
  let pointer = svgEl(s, "line", [("class", Str("pointer"))])

  let update = () => {
    let x = current(c)
    v->setTextContent(c.def.shortText(x))
    let n = clamp01(c.def.toNorm(x))
    let from = c.def.bipolar ? 0.5 : 0.
    let (a, b) = (Math.min(n, from), Math.max(n, from))
    fill->setAttribute("d", Str(b - a < 0.002 ? "" : arc(a, b, r)))
    let (px1, py1) = at(n, 0.18)
    let (px2, py2) = at(n, 0.5)
    pointer->setAttribute("x1", Num(px1))
    pointer->setAttribute("y1", Num(py1))
    pointer->setAttribute("x2", Num(px2))
    pointer->setAttribute("y2", Num(py2))
    refreshStatus(c)
  }

  valueInput(c, e)
  bind(c, update)
}

let namesOf = (def: Param.t) =>
  switch def.names {
  | Some(names) => names
  | None => JsError.panic(def.id ++ " has no value names")
  }

// What the element of a list parameter does: a click opens the menu of items(), a right
// click steps through the values (shift goes back), a middle or ctrl click picks the first.
// Space and the arrow keys step (up goes back, unless upIsNext), Enter opens the menu.
// Returns the step function.
let listInput = (ctx: Ctx.t, e, id, ~items, ~upIsNext=false) => {
  let model = ctx.model
  let count = Int.toFloat(Array.length(namesOf(model->ParamModel.def(id))))
  let current = () => model->ParamModel.get(id)
  let set = x => model->ParamModel.gestureSet(id, x)
  let step = d => set(Float.mod(Float.mod(current() + d, count) + count, count))
  let openMenu = () =>
    ctx.menu->Menu.show(e, items(), Float.toInt(current()), i => set(Int.toFloat(i)))

  e->onPointer(#pointerdown, ev => {
    ev->preventDefault
    switch ev->button {
    | 1 => set(0.)
    | 0 if ev->commandKey => set(0.)
    | 0 => openMenu()
    | 2 => step(ev->shiftKey ? -1. : 1.)
    | _ => ()
    }
  })
  e->suppressContextMenu
  let up = upIsNext ? 1. : -1.
  e->onKeyDown(ev => {
    let move = d => {
      step(d)
      ev->preventDefault
    }
    switch ev->key {
    | "ArrowUp" => move(up)
    | "ArrowDown" => move(-.up)
    | "ArrowLeft" if !upIsNext => move(-1.)
    | "ArrowRight" if !upIsNext => move(1.)
    | " " => move(1.)
    | "Enter" => openMenu()
    | _ => ()
    }
  })
  step
}

// How a list parameter's menu is laid out, when not simply in value order: the values in the
// order the menu lists them, each with the heading of the group it starts, if it starts one
// (e.g. filter types grouped by kind). App.res registers them.
let menuOrders: Map.t<string, array<(int, option<string>)>> = Map.make()

let registerMenuOrder = (id, order) => menuOrders->Map.set(id, order)

// A choice: same footprint as a parameter row; click opens the menu, right click steps
// through the values (shift goes back). Values show their icons where the plugin gave them
// some (Icons.register).
let choice = (ctx: Ctx.t, parent, id, ~x, ~y, ~w=76., ~label=?, ~names=?) => {
  let (c, e) = frame(ctx, parent, id, ~cls="p ch", ~x, ~y, ~w, ~label?, ~labelCls="l")
  let menuNames = namesOf(c.def)
  let names = names->Option.orElse(c.def.shortNames)->Option.getOr(menuNames)
  let withIcons = Icons.has(id)
  let v = el("span", ~cls=withIcons ? "v withicon" : "v", ~parent=e)
  let icon = value => Icons.forValue(id, value, menuNames[value]->Option.getOr(""))

  let update = () => {
    let x = current(c)
    let i = Float.toInt(x)
    let text = names[i]->Option.getOr(Float.toString(x))
    switch withIcons ? icon(i) : None {
    | Some(mark) =>
      v->setTextContent("")
      v->appendChild(mark)
      el("span", ~cls="lbl", ~text, ~parent=v)->ignore
    | None => v->setTextContent(text)
    }
    refreshStatus(c)
  }

  let order =
    menuOrders
    ->Map.get(id)
    ->Option.getOr(menuNames->Array.mapWithIndex((_, value) => (value, None)))
    ->Array.filter(((value, _)) => value < Array.length(menuNames))
  let step = listInput(ctx, e, id, ~items=() =>
    order->Array.map(((value, heading)) => {
      let label = menuNames[value]->Option.getOr("")
      switch withIcons ? icon(value) : None {
      | Some(icon) => {Menu.label, value, icon, ?heading}
      | None => {Menu.label, value, ?heading}
      }
    })
  )
  e->onWheel(ev => {
    ev->preventDefault
    step(ev->deltaY < 0. ? -1. : 1.)
  })
  bind(c, update)
}

// An on/off box with a label. With a width, it fills it (as in a grid cell); without, it
// is as wide as its label.
let toggle = (ctx: Ctx.t, parent, id, ~x, ~y, ~w=?, ~label=?) => {
  let (c, e) = frame(ctx, parent, id, ~cls="tg", ~x, ~y, ~w?, ~label?, ~box=true)

  let flip = () => gestureSet(c, current(c) != 0. ? 0. : 1.)
  let update = () => {
    e->toggleClass("on", current(c) != 0.)
    refreshStatus(c)
  }

  e->onPointer(#pointerdown, ev => {
    ev->preventDefault
    switch ev->button {
    | 0 => flip()
    | 1 | 2 => gestureSet(c, c.def.init)
    | _ => ()
    }
  })
  e->suppressContextMenu
  e->onActivate(flip)
  bind(c, update)
}

// (an icon goes in front of the text)
let button = (ctx: Ctx.t, parent, text, ~x, ~y, ~w, ~h=?, ~cls="", ~icon=?, ~status=?, onClick) => {
  let cls = cls == "" ? "btn" : "btn " ++ cls
  let e = switch icon {
  | Some(icon) =>
    let e = el("button", ~cls=cls ++ " withicon", ~parent)
    e->appendChild(Icons.render(icon))
    el("span", ~cls="lbl", ~text, ~parent=e)->ignore
    e
  | None => el("button", ~cls, ~text, ~parent)
  }->place(x, y, ~w, ~h?)
  e->onMouse(#click, _ => onClick())
  status->Option.forEach(status => ctx.status->Status.hover(e, () => status))
  e
}

// The corner switch of a graphical editor: swaps the graph for the raw values by toggling
// the editor's "expanded" class.
let expandSwitch = (ctx: Ctx.t, editor) => {
  let e = el("button", ~cls="btn xbtn", ~text="values", ~parent=editor)
  let expanded = ref(false)
  e->onMouse(#click, _ => {
    expanded := !expanded.contents
    editor->toggleClass("expanded", expanded.contents)
    e->setLabel(expanded.contents ? "graph" : "values")
  })
  ctx.status->Status.hover(e, () => "Switch between the graph and the raw values")
}
