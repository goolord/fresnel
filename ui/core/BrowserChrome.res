// The view runs in a web view inside the plugin window, where the browser's own context menu
// (back, refresh, print...) and shortcuts (reload, print, find, page zoom...) only get in the
// way, so they are switched off for the whole view. Text fields keep their cut/copy/paste menu.

open! Web

let inTextField = ev =>
  switch ev->originalTarget->tagNameOf {
  | Some("INPUT" | "TEXTAREA") => true
  | _ => false
  }

let isBrowserShortcut = (ev: Dom.keyboardEvent) =>
  switch ev->key->String.toLowerCase {
  | "f3" | "f5" | "f7" | "f12" => true
  | "browserback" | "browserforward" | "browserrefresh" | "browsersearch" | "browserhome" => true
  | "arrowleft" | "arrowright" | "home" if ev->altKey => true
  | "r" | "p" | "f" | "g" | "s" | "o" | "u" | "j" | "h" | "n" | "t" | "w" | "+" | "=" | "-" | "0"
    if ev->commandKey => true
  | _ => false
  }

// Returns a function that switches them back on.
let install = () => {
  let onMenu = ev =>
    if !inTextField(ev) {
      ev->preventDefault
    }
  let onKey = ev =>
    if isBrowserShortcut(ev) {
      ev->preventDefault
    }
  // ctrl-wheel (and pinch) would zoom the page
  let onWheel = ev =>
    if ev->ctrlKey {
      ev->preventDefault
    }
  document->onDocumentMouse(#contextmenu, onMenu)
  document->onDocumentKeyDown(onKey)
  document->onDocumentWheel(onWheel)
  () => {
    document->offDocumentMouse(#contextmenu, onMenu)
    document->offDocumentKeyDown(onKey)
    document->offDocumentWheel(onWheel)
  }
}
