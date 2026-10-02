// The status bar message: hover texts, or a hint about the current page when idle.

open! Web

type t = {msg: element, mutable idle: string}

let make = msg => {msg, idle: ""}

let show = (t, text) => {
  t.msg->setLabel(text)
  t.msg->removeClass("idle")
}

let clear = t => {
  t.msg->setLabel(t.idle)
  t.msg->addClass("idle")
}

let setIdle = (t, text) => {
  t.idle = text
  clear(t)
}

// Shows text() while the pointer is over e.
let hover = (t, e, text) => {
  e->onMouse(#mouseenter, _ => show(t, text()))
  e->onMouse(#mouseleave, _ => clear(t))
}

// Shows text() while the pointer is over e, and through a drag that started there: refresh
// shows it again after a change, setDragging marks the drag.
type live = {refresh: unit => unit, setDragging: bool => unit}

let live = (t, e, text) => {
  let hover = ref(false)
  let dragging = ref(false)
  let refresh = () =>
    if hover.contents || dragging.contents {
      show(t, text())
    }
  e->onMouse(#mouseenter, _ => {
    hover := true
    show(t, text())
  })
  e->onMouse(#mouseleave, _ => {
    hover := false
    if !dragging.contents {
      clear(t)
    }
  })
  let setDragging = on => {
    dragging := on
    if !on {
      hover.contents ? show(t, text()) : clear(t)
    }
  }
  {refresh, setDragging}
}
