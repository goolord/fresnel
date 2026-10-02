// A dialog over the stage: a title, the caller's rows (in `element`), then a row of buttons.

open! Web

type t = {shade: element, element: element}

let make = (stage, title) => {
  let shade = el("div", ~cls="shade", ~parent=stage)
  let element = el("div", ~cls="dlg", ~parent=shade)
  el("div", ~cls="dttl", ~text=title, ~parent=element)->ignore
  {shade, element}
}

let remove = d => d.shade->remove

// Calls close on a press on the shade beside the dialog.
let closeOnShade = (shade, close) =>
  shade->onPointer(#pointerdown, ev =>
    if ev->target === Obj.magic(shade) {
      close()
    }
  )

// Adds the buttons, (label, action) pairs, and returns them. Keys stay in the dialog (the host
// may otherwise take them as shortcuts): Enter does onEnter, except in a text area, and Escape,
// like a click beside the dialog, does close.
let finish = (d, buttons, ~onEnter, ~close) => {
  let row = el("div", ~cls="dbtns", ~parent=d.element)
  d.element->onKeyDown(k => {
    k->stopPropagation
    switch k->key {
    | "Escape" => close()
    | "Enter" if k->target->tagNameOf != Some("TEXTAREA") => onEnter()
    | _ => ()
    }
  })
  d.shade->closeOnShade(close)
  buttons->Array.map(((text, action)) => {
    let b = el("button", ~cls="btn", ~text, ~parent=row)
    b->onMouse(#click, _ => action())
    b
  })
}
