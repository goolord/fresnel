// Pop-up menus, positioned below an anchor inside the stage. A press anywhere else closes them;
// opening the menu again from the same anchor closes it instead.

open! Web

// An item may have an icon in front of its label (see Icons), a heading above it that starts
// a group, and a hint the status bar shows while the pointer is over it. Long menus run in
// columns.
type item = {label: string, value: int, icon?: element, heading?: string, hint?: string}

let rowsPerColumn = 24

type t = {
  root: element,
  status: Status.t,
  mutable menu: option<element>,
  mutable anchor: option<element>,
  // stops closing the menu on a press outside it
  mutable closer: option<unit => unit>,
}

let make = (root, ~status) => {root, status, menu: None, anchor: None, closer: None}

let close = t => {
  if Option.isSome(t.menu) {
    t.status->Status.clear
  }
  t.closer->Option.forEach(stop => stop())
  t.closer = None
  t.menu->Option.forEach(remove)
  t.menu = None
  t.anchor = None
}

let isOpenFor = (t, anchor) => t.anchor->Option.mapOr(false, a => a === anchor)

let show = (t, anchor, items, current, onPick) =>
  if isOpenFor(t, anchor) {
    close(t)
  } else {
    close(t)
    let m = el("div", ~cls="menu", ~parent=t.root)
    t.menu = Some(m)
    t.anchor = Some(anchor)
    let withIcons = items->Array.some(item => item.icon != None)
    if withIcons {
      m->addClass("icons")
    }
    let count = Array.length(items) + items->Array.filter(item => item.heading != None)->Array.length
    if count > rowsPerColumn {
      m->addClass("cols")
      m->setStyle("column-count", Int.toString((count + rowsPerColumn - 1) / rowsPerColumn))
    }
    items->Array.forEach(({label, value, ?icon, ?heading, ?hint}) => {
      heading->Option.forEach(text => el("div", ~cls="mh", ~parent=m)->setLabel(text))
      let row = el("div", ~cls=value == current ? "cur" : "", ~parent=m)
      switch icon {
      | Some(icon) => row->appendChild(icon)
      | None if withIcons => el("span", ~cls="icw", ~parent=row)->ignore
      | None => ()
      }
      el("span", ~cls="lbl", ~text=label, ~parent=row)->ignore
      hint->Option.forEach(text => t.status->Status.hover(row, () => text))
      row->onPointer(#pointerdown, ev => {
        ev->stopPropagation
        ev->preventDefault
        close(t)
        onPick(value)
      })
    })

    // position below the anchor inside the stage
    let stage = t.root
    let (x, y) = anchor->offsetWithin(stage)
    let y = y + anchor->offsetHeight
    let (width, height) = (stage->offsetWidth, stage->offsetHeight)
    m->place(0., 0.)->ignore
    let (mw, mh) = (m->offsetWidth, m->offsetHeight)
    let x = x + mw > width - 4. ? width - mw - 4. : x
    let y = y + mh > height - 4. ? Math.max(4., y - anchor->offsetHeight - mh) : y
    m->place(x, y)->ignore

    // presses on the anchor are left to it, so that it can close the menu again
    t.closer = Some(onPressOutside([m, anchor], () => close(t)))
  }

// Shows a menu at a point inside parent (in its design pixels), as if below an anchor there.
let showAt = (t, parent, ~x, ~y, items, current, onPick) => {
  let anchor = el("div", ~parent)->place(x, y, ~w=1., ~h=1.)
  anchor->setStyle("position", "absolute")
  show(t, anchor, items, current, onPick)
  anchor->remove
}
