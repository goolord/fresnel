// The optics the view shares with the DSP (dsp/FresnelDisperser.cmajor): the warped frequency axis
// the dispersion is designed on, the target group-delay curve, the colours of the spectrum, and the
// Fresnel integrals the diffraction picture is drawn with. Keep the constants in step with the DSP's.

// the axis is linear below the knee and logarithmic above (like the mel scale), up to the top,
// where the dispersion stops (the DSP lowers it to 0.4 of the sample rate below 40 kHz)
let warpKneeHz = 200.
let topHz = 16000.

// the curve the DSP sends: curvePoints frequencies from 20 Hz to 20 kHz on a log scale
let curvePoints = 256
let curveLowHz = 20.
let curveHighHz = 20000.

let blendNames = ["morph", "crossfade"]

let warp = (~top=topHz, hz) => Math.log(1. + Math.max(hz, 0.) / warpKneeHz) / Math.log(1. + top / warpKneeHz)
let unwarp = (~top=topHz, u) => warpKneeHz * (Math.pow(1. + top / warpKneeHz, ~exp=u) - 1.)

// The chroma control (-1 red .. 1 violet) as the warped position of the frequency slowed most.
let chromaPosition = (~top=topHz, chroma) => {
  let lowest = warp(~top, 20.)
  lowest + (1. - lowest) * 0.5 * (Math.max(-1., Math.min(1., chroma)) + 1.)
}
let peakHz = chroma => unwarp(chromaPosition(chroma))

// The target's shape at warped position u: a parabola of group delay peaking at c, half-width h.
let shape = (u: float, ~c: float, ~h: float) => {
  let x = (u - c) / h
  Math.max(0., 1. - x * x)
}

// The group delay (ms) the controls ask for at hz: what the DSP aims at before its sections smooth
// it and its budget limits it. width is the slit (the aperture after the envelope).
let targetMs = (hz, ~spreadMs: float, ~chroma, ~width: float) => {
  let c = chromaPosition(chroma)
  let h = Math.max(0.001, width * Math.max(c, 1. - c))
  hz >= topHz ? 0. : spreadMs * shape(warp(hz), ~c, ~h)
}

// The frequency of the curve's point i, and the point (fractional) at hz.
let curveHz = i =>
  curveLowHz * Math.pow(curveHighHz / curveLowHz, ~exp=Int.toFloat(i) / Int.toFloat(curvePoints - 1))
let curveIndex = hz =>
  Math.log(hz / curveLowHz) / Math.log(curveHighHz / curveLowHz) * Int.toFloat(curvePoints - 1)

// A curve's value at hz, between its points.
let curveAt = (curve: array<float>, hz: float) => {
  let x = Math.max(0., Math.min(Int.toFloat(curvePoints - 1), curveIndex(hz)))
  let i = Float.toInt(Math.floor(x))
  let t = x - Int.toFloat(i)
  let a = curve[i]->Option.getOr(0.)
  let b = curve[i + 1]->Option.getOr(a)
  a + (b - a) * t
}

//==============================================================================
// Colour

// The colour of light of this wavelength (nm, 380..750) as r, g, b in 0..1, dimmed towards the
// ends of the visible range (after Dan Bruton's approximation).
let wavelengthRgb = (nm: float) => {
  let (r, g, b) = if nm < 440. {
    ((440. - nm) / 60., 0., 1.)
  } else if nm < 490. {
    (0., (nm - 440.) / 50., 1.)
  } else if nm < 510. {
    (0., 1., (510. - nm) / 20.)
  } else if nm < 580. {
    ((nm - 510.) / 70., 1., 0.)
  } else if nm < 645. {
    (1., (645. - nm) / 65., 0.)
  } else {
    (1., 0., 0.)
  }
  let fade = if nm < 420. {
    0.3 + 0.7 * (nm - 380.) / 40.
  } else if nm > 700. {
    0.3 + 0.7 * (750. - nm) / 50.
  } else {
    1.
  }
  let f = Math.max(0., fade)
  (r * f, g * f, b * f)
}

// Sound as light: the bottom of the warped axis is deep red (long waves), the top violet.
let wavelengthAt = u => 680. - 270. * Math.max(0., Math.min(1., u))
let hzRgb = hz => wavelengthRgb(wavelengthAt(warp(hz)))

let cssRgb = ((r, g, b), alpha) => {
  let c = x => Int.toString(Float.toInt(Math.round(255. * Math.max(0., Math.min(1., x)))))
  `rgba(${c(r)}, ${c(g)}, ${c(b)}, ${Float.toString(alpha)})`
}

//==============================================================================
// Fresnel diffraction

// The Fresnel integrals C(x) and S(x) (Abramowitz & Stegun 7.3.32-33: the auxiliary functions'
// rational approximations, good to about 2e-3, which is plenty for a picture).
let fresnel = (x: float) => {
  let a = Math.abs(x)
  let f = (1. + 0.926 * a) / (2. + 1.792 * a + 3.104 * a * a)
  let g = 1. / (2. + 4.142 * a + 3.492 * a * a + 6.67 * a * a * a)
  let t = 0.5 * Math.Constants.pi * a * a
  let (s, c) = (Math.sin(t), Math.cos(t))
  let cx = 0.5 + f * s - g * c
  let sx = 0.5 - f * c - g * s
  x < 0. ? (-.cx, -.sx) : (cx, sx)
}

// The intensity behind a slit one unit wide, at x units from its centre, for Fresnel number nf
// (= width^2 / (wavelength * distance)): near 1 inside the slit's shadow edges with ripples at a
// large nf (near field), a broad, fringed spread at a small nf (towards far-field diffraction).
let slitIntensity = (x: float, ~nf: float) => {
  let s = Math.sqrt(2. * nf)
  let (c1, s1) = fresnel((x - 0.5) * s)
  let (c2, s2) = fresnel((x + 0.5) * s)
  let dc = c2 - c1
  let ds = s2 - s1
  0.5 * (dc * dc + ds * ds)
}
