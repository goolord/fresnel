// The dispersion drawn as light.
//
// The wavefront (make): up the side, frequency (20 Hz .. 20 kHz on a log scale), each row in the
// colour the warped axis gives it (deep red at the bottom, violet at the top); across, arrival
// time. Every frequency arrives as the image of a slit seen through Fresnel diffraction, centred on
// its group delay: a crisp, edge-rippled bar in the near field (a wide aperture, a high frequency, a
// short distance), a broad fringed blur towards the far field (a narrow aperture, a low frequency, a
// long distance). The light brightens with the input level. Over it go the group delay the DSP
// works out from its sections (phaseResponseCurve, solid) and the curve the controls ask for
// (dashed): where they part is detail finer than a section's band, which the sections can't draw.
// Until the patch sends a curve (the UI preview, a sleeping host) it draws the target alone.
//
// The slit (slit): the aperture the envelope opens and closes, with the spectrum fanning out
// behind it, red (long waves) wider than violet, as a narrower slit spreads them further.
//
// Both draw on a dark ground whatever the theme: light on a light page washes out.

open! Web

// the light field's resolution, scaled up (smoothed) to the canvas
let columns = 240
let rows = 128

// a curve older than this (ms) means the patch has gone quiet: back to the target
let stale = 1500.

@val external now: unit => float = "performance.now"

let ground = "rgb(7, 8, 13)"

// What the picture needs from the controls: the spread the target asks for (in morph, the mix
// scales it), the chroma, and the slit as set.
type controls = {spreadMs: float, chroma: float, width: float, intensity: float}

let controls = model => {
  let get = id => model->ParamModel.get(id)
  let morph = Optics.isMorph(get("blend"))
  {
    spreadMs: get("distance") * (morph ? get("mix") : 1.),
    chroma: get("chroma"),
    width: get("aperture"),
    intensity: get("intensity"),
  }
}

let controlIds = ["distance", "chroma", "aperture", "intensity", "mix", "blend"]

// The latest from the patch, shared by the drawings on a page.
type live = {
  mutable curve: option<CmajorBridge.curve>,
  mutable telemetry: option<CmajorBridge.telemetry>,
  mutable received: float,
  mutable listeners: array<unit => unit>,
}

let listen = (ctx: Ctx.t) => {
  let live = {curve: None, telemetry: None, received: -.stale, listeners: []}
  let changed = () => live.listeners->Array.forEach(f => f())
  CmajorBridge.onCurve(ctx.pc, c => {
    live.curve = Some(c)
    live.received = now()
    changed()
  })->ignore
  CmajorBridge.onTelemetry(ctx.pc, t => {
    live.telemetry = Some(t)
    changed()
  })->ignore
  live
}

let fresh = live => now() - live.received < stale

// the aperture the DSP is using, or the one set
let apertureOf = (live, c: controls) =>
  switch (fresh(live), live.telemetry) {
  | (true, Some(t)) => t.aperture
  | _ => c.width
  }

let envelopeOf = live =>
  switch (fresh(live), live.telemetry) {
  | (true, Some(t)) => t.envelope
  | _ => 0.
  }

//==============================================================================
// The wavefront

// time spans for the axis, ms, and their tick steps
let spans = [(2., 0.5), (5., 1.), (10., 2.), (20., 5.), (50., 10.), (100., 20.), (200., 50.), (500., 100.)]

// rows from the top: 20 kHz down to 20 Hz
let rowHz = r =>
  Optics.curveHighHz *
  Math.pow(Optics.curveLowHz / Optics.curveHighHz, ~exp=(Int.toFloat(r) + 0.5) / Int.toFloat(rows))

let byte = x => Float.toInt(Math.max(0., Math.min(255., x)))

// The measured curve is drawn up to here: its next points are in the parked band, where the
// delays shoot up, and a line between the two would spike.
let measuredTopHz = Optics.topHz * 0.96

let make = (ctx: Ctx.t, parent, box: box, ~live) => {
  open Context2d
  let root = el("div", ~parent)->placeBox(box)
  root->setStyle("position", "absolute")
  let canvas = CanvasStyle.make(root, {x: 0., y: 0., w: box.w, h: box.h})
  canvas->setStyle("cursor", "crosshair")
  let g = canvas->getContext2d

  // the light field, drawn small and scaled up
  let field = el("canvas")
  field->setCanvasWidth(Int.toFloat(columns))
  field->setCanvasHeight(Int.toFloat(rows))
  let fg = field->getContext2d
  let image = fg->createImageData(columns, rows)

  let readout = el("div", ~parent=root)
  [
    ("position", "absolute"),
    ("right", "10px"),
    ("top", "7px"),
    ("font-size", "11px"),
    ("color", "rgba(235, 238, 255, 0.78)"),
    ("pointer-events", "none"),
    ("font-variant-numeric", "tabular-nums"),
    ("text-align", "right"),
    ("line-height", "15px"),
  ]->Array.forEach(((k, v)) => readout->setStyle(k, v))

  // the frequency under the pointer, for the status line
  let hoverHz = ref(1000.)

  // what the light field and the readout were last worked out from: a quiet patch still sends its
  // curve some 23 times a second, and an unchanged field needn't be computed again
  let lastField = ref([])
  let lastReadout = ref([])
  // the light field for each row's delay
  let paintField = (~taus: array<float>, ~t0: float, ~t1: float, ~width: float, ~spreadMs: float, ~gain: float) => {
    let slitMs = 0.022 * (t1 - t0)
    let px = image->pixels
    taus->Array.forEachWithIndex((tau, r) => {
      let hz = rowHz(r)
      let (cr, cg, cb) = Optics.hzRgb(hz)
      let nf = Math.max(0.08, Math.min(120., (0.5 + 24. * width * width) * hz / 1000. / (1. + spreadMs / 40.)))
      // each row exposed for its own brightest (a far-field pattern spreads its light thin), and
      // dimmed above the top, where the sections are parked
      let exposure = 1. / Math.max(0.35, Optics.slitIntensity(0., ~nf))
      let dim = (hz >= Optics.topHz ? 0.25 : 1.) * exposure
      for col in 0 to columns - 1 {
        let t = t0 + (t1 - t0) * (Int.toFloat(col) + 0.5) / Int.toFloat(columns)
        let i = Math.min(1.5, Optics.slitIntensity((t - tau) / slitMs, ~nf) * gain * dim)
        let o = 4 * (r * columns + col)
        px->setPixelByte(o, byte(7. + 250. * cr * i))
        px->setPixelByte(o + 1, byte(8. + 250. * cg * i))
        px->setPixelByte(o + 2, byte(13. + 250. * cb * i))
        px->setPixelByte(o + 3, 255)
      }
    })
    fg->putImageData(image, 0., 0.)
  }

  let curveNow = () =>
    switch (fresh(live), live.curve) {
    | (true, Some(c)) => Some(c)
    | _ => None
    }

  let paint = () => {
    let c = controls(ctx.model)
    let measured = curveNow()
    let width = apertureOf(live, c)
    let targetAt = hz => Optics.targetMs(hz, ~spreadMs=c.spreadMs, ~chroma=c.chroma, ~width)
    let delayAt = hz =>
      switch measured {
      | Some(curve) if hz < measuredTopHz => Optics.curveAt(curve, hz)
      | _ => targetAt(hz)
      }

    // the span: the next that holds the longest delay with some room
    let taus = Array.fromInitializer(~length=rows, r => delayAt(rowHz(r)))
    let longest = ref(0.)
    taus->Array.forEachWithIndex((tau, r) => {
      let hz = rowHz(r)
      if hz < Optics.topHz {
        longest := Math.max(longest.contents, Math.max(tau, targetAt(hz)))
      }
    })
    let (span, step) =
      spans->Array.find(((s, _)) => s >= longest.contents * 1.15)->Option.getOr((500., 100.))
    let t0 = -0.08 * span
    let t1 = span

    // the light: Fresnel numbers fall with the slit and the wavelength (a lower frequency's
    // longer), and with the distance
    let gain = 0.55 + 0.7 * envelopeOf(live)
    let fieldKey = [t0, t1, width, c.spreadMs, gain, ...taus]
    if fieldKey != lastField.contents {
      lastField := fieldKey
      paintField(~taus, ~t0, ~t1, ~width, ~spreadMs=c.spreadMs, ~gain)
    }

    let (w, h) = (canvas->canvasWidth, canvas->canvasHeight)
    g->setFillStyle(ground)
    g->fillRect(0., 0., w, h)
    g->setImageSmoothing(true)
    g->drawImage(field, 0., 0., w, h)

    let x = t => (t - t0) / (t1 - t0) * w
    let y = hz =>
      h * (1. - Math.log(hz / Optics.curveLowHz) / Math.log(Optics.curveHighHz / Optics.curveLowHz))
    let ink = alpha => `rgba(235, 238, 255, ${Float.toString(alpha)})`
    g->setFont("18px " ++ Theme.current.contents.font)
    g->setTextBaseline("middle")

    // the parked band
    let yTop = y(Optics.topHz)
    g->setFillStyle("rgba(7, 8, 13, 0.55)")
    g->fillRect(0., 0., w, yTop)
    g->setStrokeStyle(ink(0.08))
    g->setLineWidth(1.)
    let k = ref(-.yTop)
    while k.contents < w {
      g->beginPath
      g->moveTo(k.contents, yTop)
      g->lineTo(k.contents + yTop, 0.)
      g->stroke
      k := k.contents + 14.
    }
    g->setFillStyle(ink(0.4))
    g->setTextAlign("left")
    g->fillText("sections parked", 12., yTop / 2.)

    // frequency lines and their labels
    [50., 100., 200., 500., 1000., 2000., 5000., 10000.]->Array.forEach(hz => {
      let major = hz == 100. || hz == 1000. || hz == 10000.
      CanvasStyle.hline(g, w, y(hz), ink(major ? 0.16 : 0.07))
      if major {
        g->setFillStyle(ink(0.5))
        g->fillText(Graph.hzTick(hz), 8., y(hz) - 11.)
      }
    })

    // time lines, the arrival of the undispersed sound (0) brightest
    g->setTextAlign("center")
    let t = ref(0.)
    while t.contents <= t1 + 1e-9 {
      CanvasStyle.vline(g, h, x(t.contents), ink(t.contents == 0. ? 0.28 : 0.08))
      if t.contents > 0. {
        g->setFillStyle(ink(0.5))
        let last = t.contents + step > t1
        g->setTextAlign(last ? "right" : "center")
        g->fillText(Float.toString(t.contents) ++ (last ? " ms" : ""), last ? w - 8. : x(t.contents), h - 14.)
      }
      t := t.contents + step
    }

    // the slit: the band the dispersion takes in, at the arrival line
    let ce = Optics.chromaPosition(c.chroma)
    let half = Optics.halfWidth(ce, ~width)
    let lowHz = Math.max(Optics.curveLowHz, Optics.unwarp(Math.max(0., ce - half)))
    let highHz = Math.min(Optics.topHz, Optics.unwarp(Math.min(1., ce + half)))
    if c.spreadMs > 0. {
      g->setStrokeStyle(ink(0.55 + 0.4 * envelopeOf(live)))
      g->setLineWidth(3. + 4. * envelopeOf(live))
      g->beginPath
      g->moveTo(x(0.) - 9., y(lowHz))
      g->lineTo(x(0.) - 9., y(highHz))
      g->stroke
    }

    // the target, dashed, and what the sections make of it
    let trace = (at, ~upTo=Optics.topHz, alpha, dash, lineWidth) => {
      g->setStrokeStyle(ink(alpha))
      g->setLineWidth(lineWidth)
      g->setLineDash(dash)
      g->setLineJoin("round")
      g->beginPath
      let n = 240
      for i in 0 to n {
        let hz = Optics.curveLowHz * Math.pow(upTo / Optics.curveLowHz, ~exp=Int.toFloat(i) / Int.toFloat(n))
        let (px, py) = (x(at(hz)), y(hz))
        i == 0 ? g->moveTo(px, py) : g->lineTo(px, py)
      }
      g->stroke
      g->setLineDash([])
    }
    trace(targetAt, 0.45, [7., 6.], 1.5)
    measured->Option.forEach(curve => trace(hz => Optics.curveAt(curve, hz), ~upTo=measuredTopHz, 0.75, [], 1.6))

    // the numbers
    let spread = switch (measured, live.telemetry) {
    | (Some(_), Some(t)) => Param.msText(t.spread)
    | _ => Param.msText(c.spreadMs) ++ " (target)"
    }
    let budget = switch (measured, live.telemetry) {
    | (Some(_), Some(t)) => `${Float.toFixed(t.budget * 100., ~digits=0)} % of the glass`
    | _ => ""
    }
    let lines = [`spread ${spread}`, `peak ${Param.hzText(Optics.peakHz(c.chroma))}`, budget]->Array.filter(s => s != "")
    if lines != lastReadout.contents {
      lastReadout := lines
      readout->setTextContent("")
      lines->Array.forEach(s => el("div", ~text=s, ~parent=readout)->ignore)
    }
  }

  let redraw = perFrame(() =>
    if root->offsetParent->Option.isSome {
      paint()
    }
  )

  let status = ctx.status->Status.live(canvas, () => {
    let hz = hoverHz.contents
    let c = controls(ctx.model)
    let target = Optics.targetMs(hz, ~spreadMs=c.spreadMs, ~chroma=c.chroma, ~width=apertureOf(live, c))
    let made = switch curveNow() {
    | Some(curve) => `, the sections make ${Param.msText(Optics.curveAt(curve, hz))}`
    | None => ""
    }
    hz >= Optics.topHz
      ? `${Param.hzText(hz)}: above the dispersion, where the unused sections are parked`
      : `${Param.hzText(hz)} arrives ${Param.msText(target)} late${made}`
  })
  canvas->onMouse(#mousemove, ev => {
    let (_, fy) = pointerFraction(canvas, ev)
    hoverHz :=
      Optics.curveLowHz * Math.pow(Optics.curveHighHz / Optics.curveLowHz, ~exp=1. - Math.max(0., Math.min(1., fy)))
    status.refresh()
  })

  live.listeners->Array.push(redraw)
  ctx.model->ParamModel.listenEach(controlIds, redraw)
  CanvasStyle.onThemeChange(redraw)
  // the page may be built hidden: draw once it shows
  let observer = makeResizeObserver(redraw)
  observer->observe(root)
  redraw()
  root
}

//==============================================================================
// The slit

let slit = (ctx: Ctx.t, parent, box: box, ~live) => {
  open Context2d
  let root = el("div", ~parent)->placeBox(box)
  root->setStyle("position", "absolute")
  let canvas = CanvasStyle.make(root, {x: 0., y: 0., w: box.w, h: box.h})
  let g = canvas->getContext2d

  let paint = () => {
    let (w, h) = (canvas->canvasWidth, canvas->canvasHeight)
    let c = controls(ctx.model)
    let width = apertureOf(live, c)
    let env = envelopeOf(live)
    let ink = alpha => `rgba(235, 238, 255, ${Float.toString(alpha)})`
    g->setFillStyle(ground)
    g->fillRect(0., 0., w, h)

    let xs = w * 0.3
    let yc = h * 0.46
    let beamHalf = h * 0.3
    let gap = Math.max(1.5, beamHalf * width)
    let set = Math.max(1.5, beamHalf * c.width)

    // the light coming in, a plane wave as bright as the input is loud
    g->setFillStyle(ink(0.03 + 0.12 * env))
    g->fillRect(0., yc - beamHalf, xs, 2. * beamHalf)
    g->setStrokeStyle(ink(0.1 + 0.4 * env))
    g->setLineWidth(1.)
    let front = ref(10.)
    while front.contents < xs - 8. {
      g->beginPath
      g->moveTo(CanvasStyle.snap(front.contents), yc - beamHalf)
      g->lineTo(CanvasStyle.snap(front.contents), yc + beamHalf)
      g->stroke
      front := front.contents + 12.
    }

    // Behind the slit: the central band, and each colour's first fringes either side, at
    // sin (angle) = wavelength / slit, so a longer wave (red) lands further out, and a narrower
    // slit throws them all wider.
    let wedge = (from, to_, colour) => {
      let reach = w - xs
      g->setFillStyle(colour)
      g->beginPath
      g->moveTo(xs, yc)
      g->lineTo(w, yc - Math.tan(from) * reach)
      g->lineTo(w, yc - Math.tan(to_) * reach)
      g->closePath
      g->fill
    }
    let angle = nm => Math.asin(Math.min(0.97, 0.00026 * nm / Math.max(0.03, width)))
    let glow = 0.25 + 0.6 * env
    g->setCompositeOperation("lighter")
    let centre = 0.55 * angle(550.)
    wedge(-.centre, centre, ink(0.12 + 0.3 * env))
    [680., 640., 600., 570., 540., 510., 480., 450., 420.]->Array.forEach(nm => {
      let a = angle(nm)
      let d = 0.07 * a
      let colour = Optics.cssRgb(Optics.wavelengthRgb(nm), glow)
      wedge(a - d, a + d, colour)
      wedge(-.a - d, -.a + d, colour)
    })
    g->setCompositeOperation("source-over")

    // the screen and its jaws, and where the aperture is set (the envelope moves them from there)
    g->setFillStyle(Theme.rgb(Theme.current.contents.panelHi))
    g->fillRect(xs - 5., 0., 10., yc - gap)
    g->fillRect(xs - 5., yc + gap, 10., h - yc - gap)
    g->setStrokeStyle(ink(0.6))
    g->setLineWidth(1.)
    g->setLineDash([3., 3.])
    [yc - set, yc + set]->Array.forEach(yy => {
      g->beginPath
      g->moveTo(xs - 16., yy)
      g->lineTo(xs + 16., yy)
      g->stroke
    })
    g->setLineDash([])

    // the input level, along the bottom
    g->setFillStyle(ink(0.1))
    g->fillRect(10., h - 16., w - 20., 6.)
    g->setFillStyle(ink(0.75))
    g->fillRect(10., h - 16., (w - 20.) * env, 6.)

    g->setFont("18px " ++ Theme.current.contents.font)
    g->setTextBaseline("middle")
    g->setTextAlign("left")
    g->setFillStyle(ink(0.6))
    let direction = c.intensity > 0. ? "narrows" : c.intensity < 0. ? "widens" : "leaves"
    g->fillText(
      `slit ${Float.toFixed(width * 100., ~digits=0)} %  (set ${Float.toFixed(c.width * 100., ~digits=0)} %)`,
      12.,
      18.,
    )
    g->fillText(`level ${direction} it`, 12., h - 34.)
  }

  let redraw = perFrame(() =>
    if root->offsetParent->Option.isSome {
      paint()
    }
  )
  ctx.status->Status.hover(canvas, () =>
    "The slit: the input level moves its jaws (Intensity) from where Aperture sets them (dashed); a narrower slit disperses a narrower band"
  )
  live.listeners->Array.push(redraw)
  ctx.model->ParamModel.listenEach(controlIds, redraw)
  CanvasStyle.onThemeChange(redraw)
  let observer = makeResizeObserver(redraw)
  observer->observe(root)
  redraw()
  root
}
