// Bindings to the browser APIs the view uses.

type element = Dom.element

@val external document: Dom.document = "document"
@send external createElement: (Dom.document, string) => element = "createElement"
@send external createElementNS: (Dom.document, string, string) => element = "createElementNS"
@get external body: Dom.document => element = "body"
@get external documentElement: Dom.document => element = "documentElement"

//==============================================================================
// Elements

@send external appendChild: (Dom.node_like<'a>, element) => unit = "appendChild"
@send external remove: element => unit = "remove"
@send external contains: (element, Dom.eventTarget) => bool = "contains"
@send @return(nullable)
external querySelector: (element, string) => option<element> = "querySelector"
@send external querySelectorAll: (element, string) => Dom.nodeList = "querySelectorAll"
@val external nodesToArray: Dom.nodeList => array<element> = "Array.from"
@get @return(nullable) external parentElement: element => option<element> = "parentElement"
@set external setClassName: (element, string) => unit = "className"
@set external setTextContent: (element, string) => unit = "textContent"
@set external setTabIndex: (element, int) => unit = "tabIndex"
@send external focus: element => unit = "focus"
@send external click: element => unit = "click"
@send external setPointerCapture: (element, int) => unit = "setPointerCapture"

// Attribute values: numbers are written the way JavaScript prints them.
@unboxed type attr = Num(float) | Str(string)
@send external setAttribute: (element, string, attr) => unit = "setAttribute"

type classList
@get external classList: element => classList = "classList"
@send external addClass: (classList, string) => unit = "add"
@send external removeClass: (classList, string) => unit = "remove"
@send external toggleClass: (classList, string, bool) => bool = "toggle"

let addClass = (e, name) => e->classList->addClass(name)
let removeClass = (e, name) => e->classList->removeClass(name)
let toggleClass = (e, name, on) => e->classList->toggleClass(name, on)->ignore

type style
@get external style: element => style = "style"
@send external setProperty: (style, string, string) => unit = "setProperty"
@set external setCssText: (style, string) => unit = "cssText"

let setStyle = (e, property, value) => e->style->setProperty(property, value)
let px = x => Float.toString(x) ++ "px"

type cssStyleDeclaration
@val external getComputedStyle: element => cssStyleDeclaration = "getComputedStyle"
@send external getPropertyValue: (cssStyleDeclaration, string) => string = "getPropertyValue"

// Layout
@get external offsetLeft: element => float = "offsetLeft"
@get external offsetTop: element => float = "offsetTop"
@get external offsetWidth: element => float = "offsetWidth"
@get external offsetHeight: element => float = "offsetHeight"
@get @return(nullable) external offsetParent: element => option<element> = "offsetParent"
@get external clientWidth: element => float = "clientWidth"
@get external clientHeight: element => float = "clientHeight"
@get external scrollTop: element => float = "scrollTop"
@set external setScrollTop: (element, float) => unit = "scrollTop"

type rect = {left: float, top: float, width: float, height: float}
@send external getBoundingClientRect: element => rect = "getBoundingClientRect"

// Text inputs
@get external value: element => string = "value"
@set external setValue: (element, string) => unit = "value"
@set external setMaxLength: (element, int) => unit = "maxLength"
@set external setInputType: (element, string) => unit = "type"
@set external setAccept: (element, string) => unit = "accept"
@set external setMultiple: (element, bool) => unit = "multiple"
@set external setPlaceholder: (element, string) => unit = "placeholder"
@set external setSpellcheck: (element, bool) => unit = "spellcheck"
@send external select: element => unit = "select"
@send external blur: element => unit = "blur"

// Links
@set external setHref: (element, string) => unit = "href"
@set external setDownload: (element, string) => unit = "download"

// Shadow DOM
type shadowInit = {mode: string}
@send external attachShadow: (element, shadowInit) => Dom.shadowRoot = "attachShadow"

//==============================================================================
// Events

@get external button: Dom.mouseEvent_like<'a> => int = "button"
@get external clientX: Dom.mouseEvent_like<'a> => float = "clientX"
@get external clientY: Dom.mouseEvent_like<'a> => float = "clientY"
@get external pointerId: Dom.pointerEvent => int = "pointerId"
@get external deltaY: Dom.wheelEvent => float = "deltaY"
@get external key: Dom.keyboardEvent => string = "key"
@get external shiftKey: Dom.uiEvent_like<'a> => bool = "shiftKey"
@get external ctrlKey: Dom.uiEvent_like<'a> => bool = "ctrlKey"
@get external metaKey: Dom.uiEvent_like<'a> => bool = "metaKey"
@get external altKey: Dom.uiEvent_like<'a> => bool = "altKey"
@get external target: Dom.event_like<'a> => Dom.eventTarget = "target"
@send external composedPath: Dom.event_like<'a> => array<Dom.eventTarget> = "composedPath"
@send external preventDefault: Dom.event_like<'a> => unit = "preventDefault"
@send external stopPropagation: Dom.event_like<'a> => unit = "stopPropagation"
@send external stopImmediatePropagation: Dom.event_like<'a> => unit = "stopImmediatePropagation"

// device pixels per CSS pixel
@val external devicePixelRatio: float = "devicePixelRatio"

// The element an event started on, also seen from outside the view's shadow root (where
// target is the shadow host).
let originalTarget = ev => ev->composedPath->Array.get(0)->Option.getOr(ev->target)

// ctrl, or cmd on a Mac
let commandKey = ev => ev->ctrlKey || ev->metaKey

// Where a pointer is over an element, as fractions of its width and height.
let pointerFraction = (e, ev) => {
  let r = e->getBoundingClientRect
  ((ev->clientX - r.left) / r.width, (ev->clientY - r.top) / r.height)
}

type pointerEventName = [#pointerdown | #pointermove | #pointerup | #pointercancel]
type mouseEventName = [#mouseenter | #mouseleave | #mousemove | #click | #dblclick | #contextmenu]
type dragEventName = [#dragenter | #dragleave | #dragover | #drop]

@send
external onPointer: (element, pointerEventName, Dom.pointerEvent => unit) => unit =
  "addEventListener"
@send
external offPointer: (element, pointerEventName, Dom.pointerEvent => unit) => unit =
  "removeEventListener"
// in the capture phase: before the element's own listeners and its children's
@send
external onPointerCapture: (
  element,
  pointerEventName,
  Dom.pointerEvent => unit,
  @as(json`true`) _,
) => unit = "addEventListener"
@send
external onMouse: (element, mouseEventName, Dom.mouseEvent => unit) => unit = "addEventListener"
@send
external onWheel: (
  element,
  @as("wheel") _,
  Dom.wheelEvent => unit,
  @as(json`{"passive": false}`) _,
) => unit = "addEventListener"
@send
external onKeyDown: (element, @as("keydown") _, Dom.keyboardEvent => unit) => unit =
  "addEventListener"
@send external onDrag: (element, dragEventName, Dom.dragEvent => unit) => unit = "addEventListener"
@send
external onEvent: (element, [#change | #blur | #input], Dom.event => unit) => unit = "addEventListener"

@send
external onDocumentPointerDownCapture: (
  Dom.document,
  @as("pointerdown") _,
  Dom.pointerEvent => unit,
  @as(json`true`) _,
) => unit = "addEventListener"
@send
external offDocumentPointerDownCapture: (
  Dom.document,
  @as("pointerdown") _,
  Dom.pointerEvent => unit,
  @as(json`true`) _,
) => unit = "removeEventListener"

@send
external onDocumentMouse: (Dom.document, mouseEventName, Dom.mouseEvent => unit) => unit =
  "addEventListener"
@send
external offDocumentMouse: (Dom.document, mouseEventName, Dom.mouseEvent => unit) => unit =
  "removeEventListener"
@send
external onDocumentKeyDown: (Dom.document, @as("keydown") _, Dom.keyboardEvent => unit) => unit =
  "addEventListener"
@send
external offDocumentKeyDown: (Dom.document, @as("keydown") _, Dom.keyboardEvent => unit) => unit =
  "removeEventListener"
@send
external onDocumentWheel: (
  Dom.document,
  @as("wheel") _,
  Dom.wheelEvent => unit,
  @as(json`{"passive": false}`) _,
) => unit = "addEventListener"
@send
external offDocumentWheel: (Dom.document, @as("wheel") _, Dom.wheelEvent => unit) => unit =
  "removeEventListener"

// The tag of an event target, e.g. "INPUT" (None for the document or the window).
@get @return(nullable) external tagNameOf: Dom.eventTarget => option<string> = "tagName"

// Calls onOutside on a press anywhere but in the elements inside, from the next turn of the event
// loop on (so not for the press that is opening something now). Returns the function that stops it.
let onPressOutside = (inside, onOutside) => {
  let listener = ev => {
    let target = ev->originalTarget
    if !(inside->Array.some(e => e->contains(target))) {
      onOutside()
    }
  }
  let timer = setTimeout(() => document->onDocumentPointerDownCapture(listener), 0)
  () => {
    clearTimeout(timer)
    document->offDocumentPointerDownCapture(listener)
  }
}

// Ignores the context menu, so that right-button drags and clicks reach the control.
let suppressContextMenu = e => e->onMouse(#contextmenu, preventDefault)

// Calls f when Enter or Space is pressed on a focused element, as a click would.
let onActivate = (e, f) =>
  e->onKeyDown(ev =>
    if ev->key == "Enter" || ev->key == " " {
      ev->preventDefault
      f()
    }
  )

//==============================================================================
// Files

type file
type fileList
type dataTransfer
@get external fileName: file => string = "name"

// A file name without its extension.
let baseName = name =>
  switch name->String.lastIndexOf(".") {
  | i if i > 0 => name->String.slice(~start=0, ~end=i)
  | _ => name
  }
@send external arrayBuffer: file => promise<ArrayBuffer.t> = "arrayBuffer"
@send @return(nullable) external item: (fileList, int) => option<file> = "item"
@val external filesToArray: fileList => array<file> = "Array.from"
@get @return(nullable) external files: element => option<fileList> = "files"
@get @return(nullable) external dataTransfer: Dom.dragEvent => option<dataTransfer> = "dataTransfer"
@get external transferredFiles: dataTransfer => fileList = "files"

// What to tell the user when reading a file threw e.
let readError = (file, e) => `Couldn't read ${file->fileName}: ${e->JsExn.message->Option.getOr("")}`

// A file's bytes, or the readError.
let readBytes = async file =>
  try Ok(Uint8Array.fromBuffer(await file->arrayBuffer)) catch {
  | JsExn(e) => Error(readError(file, e))
  }

type blob
type blobOptions = {@as("type") mimeType: string}
@new external makeBlob: (array<Uint8Array.t>, blobOptions) => blob = "Blob"
@val external createObjectURL: blob => string = "URL.createObjectURL"
@val external revokeObjectURL: string => unit = "URL.revokeObjectURL"

//==============================================================================
// Canvas

type context2d
@set external setCanvasWidth: (element, float) => unit = "width"
@set external setCanvasHeight: (element, float) => unit = "height"
@get external canvasWidth: element => float = "width"
@get external canvasHeight: element => float = "height"
@send external getContext2d: (element, @as("2d") _) => context2d = "getContext"

module Context2d = {
  @set external setFillStyle: (context2d, string) => unit = "fillStyle"
  @set external setStrokeStyle: (context2d, string) => unit = "strokeStyle"
  @set external setLineWidth: (context2d, float) => unit = "lineWidth"
  @send external clearRect: (context2d, float, float, float, float) => unit = "clearRect"
  @send external fillRect: (context2d, float, float, float, float) => unit = "fillRect"
  @send external strokeRect: (context2d, float, float, float, float) => unit = "strokeRect"
  @send external beginPath: context2d => unit = "beginPath"
  @send external closePath: context2d => unit = "closePath"
  @send external moveTo: (context2d, float, float) => unit = "moveTo"
  @send external lineTo: (context2d, float, float) => unit = "lineTo"
  @send external stroke: context2d => unit = "stroke"
  @send external fill: context2d => unit = "fill"
  @send external setLineDash: (context2d, array<float>) => unit = "setLineDash"
  @set external setLineJoin: (context2d, string) => unit = "lineJoin"
  @set external setGlobalAlpha: (context2d, float) => unit = "globalAlpha"
  // "source-over", "lighter" (additive, for light), "screen"...
  @set external setCompositeOperation: (context2d, string) => unit = "globalCompositeOperation"
  @set external setFont: (context2d, string) => unit = "font"
  @set external setTextAlign: (context2d, string) => unit = "textAlign"
  @set external setTextBaseline: (context2d, string) => unit = "textBaseline"
  @send external fillText: (context2d, string, float, float) => unit = "fillText"
  @set external setImageSmoothing: (context2d, bool) => unit = "imageSmoothingEnabled"
  // draws a canvas (or image) into a rectangle, scaled
  @send external drawImage: (context2d, element, float, float, float, float) => unit = "drawImage"

  // pixels: an RGBA byte per channel, row by row
  type imageData
  type pixels
  @send external createImageData: (context2d, int, int) => imageData = "createImageData"
  @get external pixels: imageData => pixels = "data"
  @set_index external setPixelByte: (pixels, int, int) => unit = ""
  @send external putImageData: (context2d, imageData, float, float) => unit = "putImageData"
}

//==============================================================================
// Scheduling and observers

@val external requestAnimationFrame: (float => unit) => unit = "requestAnimationFrame"

// Wraps f so that a burst of calls runs it once, when schedule calls back.
let coalesce = (schedule, f) => {
  let pending = ref(false)
  () =>
    if !pending.contents {
      pending := true
      schedule(() => {
        pending := false
        f()
      })
    }
}

// Wraps f so that any number of calls before the next frame run it once, in that frame.
let perFrame = f => coalesce(run => requestAnimationFrame(_ => run()), f)

type resizeObserver
@new external makeResizeObserver: (unit => unit) => resizeObserver = "ResizeObserver"
@send external observe: (resizeObserver, element) => unit = "observe"
@send external disconnect: resizeObserver => unit = "disconnect"

//==============================================================================
// Custom elements

type elementClass
@scope("customElements") @val @return(nullable)
external getCustomElement: string => option<elementClass> = "get"
@scope("customElements") @val
external defineCustomElement: (string, elementClass) => unit = "define"

//==============================================================================
// Building

// Sets a single-line label: the text in a <span class="lbl">, which the stylesheet trims to the
// height of the capitals, so that the label sits in the middle of its box whatever the font's
// ascent and descent (a font's line box isn't centred on its letters: Bahnschrift's puts them a
// pixel high, Segoe UI's low). Buttons get their text this way; use it for any fixed-height label.
let setLabel = (e, text) => {
  e->setTextContent("")
  let span = document->createElement("span")
  span->setClassName("lbl")
  span->setTextContent(text)
  e->appendChild(span)
}

// Creates an element, optionally with a class, text (a label, for a button), and a parent to
// append it to.
let el = (tag, ~cls=?, ~text=?, ~parent=?) => {
  let e = document->createElement(tag)
  cls->Option.forEach(cls => e->setClassName(cls))
  text->Option.forEach(text => tag == "button" ? e->setLabel(text) : e->setTextContent(text))
  parent->Option.forEach(parent => parent->appendChild(e))
  e
}

// A rectangle in design pixels.
type box = {x: float, y: float, w: float, h: float}

// Positions an element in design pixels.
let place = (e, x, y, ~w=?, ~h=?) => {
  e->setStyle("left", px(x))
  e->setStyle("top", px(y))
  w->Option.forEach(w => e->setStyle("width", px(w)))
  h->Option.forEach(h => e->setStyle("height", px(h)))
  e
}

let placeBox = (e, {x, y, w, h}) => e->place(x, y, ~w, ~h)

let svgNamespace = "http://www.w3.org/2000/svg"

// Creates an SVG element with these attributes, inside a parent.
let svgEl = (parent, tag, attrs) => {
  let e = document->createElementNS(svgNamespace, tag)
  attrs->Array.forEach(((name, value)) => e->setAttribute(name, value))
  parent->appendChild(e)
  e
}

// The position of an element relative to an ancestor, following offsetParent.
let offsetWithin = (e, ancestor) => {
  let rec go = (node, x, y) =>
    switch node {
    | Some(n) if n !== ancestor => go(n->offsetParent, x + n->offsetLeft, y + n->offsetTop)
    | _ => (x, y)
    }
  go(Some(e), 0., 0.)
}
