// The plugin's parameters: the one list the view, the host and the DSP share. tools/gen.mjs turns it
// into dsp/Params.cmajor (the endpoints, and a params::Values struct the DSP reads by name), so
// after changing it run `just gen` (every build does).
//
// Ids are Cmajor identifiers and are how hosts and presets know a parameter: append, and rename
// with care. Ranges and defaults are plain values (Hz, ms, dB). A `logarithmic` knob hands the DSP
// its frequency or time but keeps its position for hosts to automate.
//
// The Fresnel disperser's controls (dsp/FresnelDisperser.cmajor, docs/dispersion.md):
//   distance   z: the group-delay spread, from glassy phase alignment to liquid chirp smearing
//   chroma     lambda: which frequency is slowed the most, red (lows lag) to violet (highs lag)
//   aperture   the slit: how wide a band around that frequency is dispersed
//   intensity  how much the input level narrows (or, below 0, widens) the slit
//   mix        how much of the dispersion is heard; `blend` says how (see Optics.blendNames)

open Param

let all = [
  number("distance", "Distance", ~min=0., ~max=250., ~init=12., ~unit="ms", ~law=Power(3.)),
  number("chroma", "Chroma", ~min=-1., ~max=1., ~init=0.35, ~text=x => hzText(Optics.peakHz(x))),
  number("aperture", "Aperture", ~min=0.05, ~max=1., ~init=0.7, ~unit="%", ~digits=0),
  number("intensity", "Intensity", ~min=-1., ~max=1., ~init=0.25, ~unit="%", ~digits=0),
  number("mix", "Mix", ~min=0., ~max=1., ~init=1., ~unit="%", ~digits=0),
  // morph scales the dispersion itself (never combs); crossfade blends the dry and dispersed
  // signals (combs in and around the dispersed band, the classic phaser-like blend)
  choice("blend", "Blend", Optics.blendNames),
  number("level", "Output", ~min=-24., ~max=12., ~init=0., ~unit="dB"),
]
