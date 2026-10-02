// A panel: a block with a title, or with a strip of tabs that each show one body.
// Bodies cover the whole panel, so grid coordinates are the same in every tab.

open! Web

type t = {
  el: element,
  x: float,
  y: float,
  w: float,
  h: float,
  tabs: array<element>,
  bodies: array<element>,
  mutable current: int,
  onSelect: int => unit,
}

let show = (p, i) => {
  p.current = i
  p.tabs->Array.forEachWithIndex((tab, k) => tab->toggleClass("on", k == i))
  p.bodies->Array.forEachWithIndex((body, k) => body->toggleClass("on", k == i))
}

let select = (p, i) => {
  show(p, i)
  p.onSelect(i)
}

// With tabs, there is one body per tab (unless bodies is false, for a panel that redraws
// itself in onSelect); without, the panel itself is the only body.
let make = (parent, ~title="", ~tabs=[], ~bodies=true, ~onSelect=_ => (), ~x, ~y, ~w, ~h) => {
  let e = Controls.block(parent, title, ~x, ~y, ~w, ~h)
  let strip = el("div", ~cls="ptabs", ~parent=e)
  let p = {
    el: e,
    x,
    y,
    w,
    h,
    tabs: tabs->Array.map(label => {
      let tab = el("div", ~cls="ptab", ~parent=strip)
      tab->setLabel(label)
      tab
    }),
    bodies: bodies ? tabs->Array.map(_ => el("div", ~cls="pbody", ~parent=e)) : [],
    current: 0,
    onSelect,
  }
  p.tabs->Array.forEachWithIndex((tab, i) => tab->onPointer(#pointerdown, _ => select(p, i)))
  if tabs == [] {
    strip->remove
  } else {
    show(p, 0)
  }
  p
}

let body = (p, i) => p.bodies[i]->Option.getOr(p.el)

let right = p => p.x + p.w + Grid.gap
let bottom = p => p.y + p.h + Grid.gap

// A switch at the right end of the title row, e.g. an effect's on switch.
let headerToggle = (p, ctx, id, ~label) =>
  Controls.toggle(ctx, el("div", ~cls="hdr", ~parent=p.el), id, ~x=0., ~y=0., ~label)
