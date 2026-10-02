// What a parameter is. A plugin lists its parameters as specs (ui/plugin/Params.res); tools/gen.mjs
// turns the same list into the patch's endpoints (dsp/Params.cmajor), so the view, the host and
// the DSP always agree. The view works with defs: a spec with its knob law, texts and parsing
// worked out.
//
// A parameter's *value* is what its endpoint holds and the host automates; the DSP receives its
// *plain* value (Hz, ms, dB...). They are the same except on an Exp knob, whose endpoint holds
// the knob's position 0..1 (so that hosts automate a frequency as it turns, on a log scale) and
// whose plain value is lo * (hi / lo) ^ position.

// How a knob's travel maps to the value.
type law =
  | Linear
  // a log scale from min to max (both above 0): the endpoint holds the position 0..1
  | Exp
  // min + (max - min) * position ^ power: more travel at the low end with power > 1; the
  // endpoint holds the value
  | Power(float)

type number = {
  min: float,
  max: float,
  // the default, as a plain value
  init: float,
  law?: law,
  // "Hz", "ms", "s", "dB", "%" (a 0..1 value shown as a percentage), "st", "ct", "x", "°" or any
  // text to put after the number
  unit?: string,
  // digits after the point (default: a few significant digits)
  digits?: int,
  // a text of its own for a plain value, instead of the number and its unit
  text?: float => string,
}

type kind =
  | Number(number)
  // a list: the endpoint holds the index
  | Choice({names: array<string>, init: int, short?: array<string>})
  | Toggle({init: bool})

type spec = {
  // the endpoint's name: a Cmajor identifier, which hosts and presets know the parameter by, so
  // don't change it once presets exist
  id: string,
  // what hosts and the status line call it
  name: string,
  kind: kind,
  // left out of the host's parameters (still an endpoint, saved with the session's state, and in presets)
  hidden?: bool,
}

//==============================================================================
// Texts

let fixed = (x, digits) => Float.toFixed(x, ~digits)

// a few significant digits: 1234, 123.4, 12.34, 1.234
let auto = (x: float) => {
  let a = Math.abs(x)
  fixed(x, a >= 1000. ? 0 : a >= 100. ? 1 : a >= 10. ? 2 : a >= 0.0001 || a == 0. ? 3 : 5)
}

let hzText = (~digits=?, x: float) =>
  x >= 1000.
    ? fixed(x / 1000., digits->Option.getOr(x >= 10000. ? 1 : 2)) ++ " kHz"
    : fixed(x, digits->Option.getOr(x < 100. ? 1 : 0)) ++ " Hz"
let msText = (~digits=?, x: float) =>
  x >= 1000.
    ? fixed(x / 1000., digits->Option.getOr(2)) ++ " s"
    : fixed(x, digits->Option.getOr(x < 10. ? 2 : x < 100. ? 1 : 0)) ++ " ms"
let signed = (x: float, s) => (x > 0. ? "+" : "") ++ s
let dbText = (~digits=1, x: float) => x <= -120. ? "-inf dB" : signed(x, fixed(x, digits)) ++ " dB"
let percentText = (~digits=1, x: float) => fixed(x * 100., digits) ++ " %"

let numberText = (n: number, x) =>
  switch (n.text, n.unit) {
  | (Some(text), _) => text(x)
  | (None, Some("Hz")) => hzText(~digits=?n.digits, x)
  | (None, Some("ms")) => msText(~digits=?n.digits, x)
  | (None, Some("dB")) => dbText(~digits=?n.digits, x)
  | (None, Some("%")) => n.min < 0. ? signed(x, percentText(~digits=?n.digits, x)) : percentText(~digits=?n.digits, x)
  | (None, unit) =>
    let s = switch n.digits {
    | Some(d) => fixed(x, d)
    | None => auto(x)
    }
    let s = n.min < 0. ? signed(x, s) : s
    switch unit {
    | Some("°") => s ++ "°"
    | Some(u) => s ++ " " ++ u
    | None => s
    }
  }

// A typed number in the parameter's units: "1.5k" and "2 kHz" are thousands, "300 ms" in a seconds
// field is 0.3, a percentage is a hundredth.
let readNumber = (n: number, text) => {
  let lower = String.toLowerCase(String.trim(text))
  let x = Float.parseFloat(lower)
  if !Float.isFinite(x) {
    lower == "-inf" ? Some(n.min) : None
  } else {
    let x = switch n.unit {
    | Some("%") => x / 100.
    | Some("Hz") if String.includes(lower, "k") => x * 1000.
    | Some("ms") if String.endsWith(lower, "s") && !String.endsWith(lower, "ms") => x * 1000.
    | Some("s") if String.endsWith(lower, "ms") => x / 1000.
    | _ => x
    }
    Some(x)
  }
}

//==============================================================================
// Defs

type t = {
  id: string,
  // its place in the plugin's list, which is also its slot in the DSP's mirror
  index: int,
  name: string,
  isInt: bool,
  hidden: bool,
  // value names for menus and the status bar, and compact ones for narrow fields
  names: option<array<string>>,
  shortNames: option<array<string>>,
  // the value's default, range (the endpoint's), and whether it swings both ways from 0
  init: float,
  min: float,
  max: float,
  bipolar: bool,
  clamp: float => float,
  // knob position 0..1 <-> value
  toNorm: float => float,
  fromNorm: float => float,
  // value <-> plain value
  plain: float => float,
  ofPlain: float => float,
  // "Cutoff: 1.20 kHz" for the status line, "1.20 kHz", and the compact text for narrow fields
  longText: float => string,
  valueText: float => string,
  shortText: float => string,
  // a typed text (in the plain units) to a value
  parse: string => option<float>,
  // the unit the host shows (only where the value is the plain value)
  unit: option<string>,
}

let clampTo = (lo: float, hi: float, fallback, x) => Float.isFinite(x) ? Math.max(lo, Math.min(hi, x)) : fallback

// "1392.5 Hz" -> fits a narrow field: at most five significant digits
let compact = s =>
  s->String.replaceRegExpBy3Unsafe(/^([-+]?)(\d+)\.(\d+)/, (
    ~match,
    ~group1 as sign,
    ~group2 as whole,
    ~group3 as fraction,
    ~offset as _,
    ~input as _,
  ) => {
    let digits = String.length(whole)
    if digits >= 5 {
      sign ++ whole
    } else if digits + String.length(fraction) > 5 {
      sign ++ whole ++ "." ++ String.slice(fraction, ~start=0, ~end=5 - digits)
    } else {
      match
    }
  })

let nameIndex = (names, s) =>
  names
  ->Array.findIndex(n => String.toLowerCase(n) == String.toLowerCase(String.trim(s)))
  ->(i => i >= 0 ? Some(Int.toFloat(i)) : None)

let make = (index, spec: spec): t => {
  let {id, name} = spec
  let hidden = spec.hidden->Option.getOr(false)
  let withName = valueText => x => `${name}: ${valueText(x)}`
  switch spec.kind {
  | Number(n) =>
    let law = n.law->Option.getOr(Linear)
    let (lo, hi) = (n.min, n.max)
    let span = hi - lo
    // the endpoint's range, and value <-> plain value
    let (min, max, plain, ofPlain) = switch law {
    | Exp => (0., 1., v => lo * Math.pow(hi / lo, ~exp=v), x => Math.log(Math.max(x, lo) / lo) / Math.log(hi / lo))
    | Linear | Power(_) => (lo, hi, x => x, x => x)
    }
    let init = clampTo(min, max, min, ofPlain(n.init))
    let clamp = clampTo(min, max, init, ...)
    let (toNorm, fromNorm) = switch law {
    | Exp => (x => x, v => v)
    | Linear => (x => span == 0. ? 0. : (x - lo) / span, v => lo + span * v)
    | Power(p) => (
        x => span == 0. ? 0. : Math.pow(Math.max(0., (x - lo) / span), ~exp=1. / p),
        v => lo + span * Math.pow(Math.max(0., v), ~exp=p),
      )
    }
    let valueText = x => numberText(n, plain(x))
    {
      id,
      index,
      name,
      isInt: false,
      hidden,
      names: None,
      shortNames: None,
      init,
      min,
      max,
      bipolar: lo < 0. && hi > 0.,
      clamp,
      toNorm,
      fromNorm,
      plain,
      ofPlain,
      longText: withName(valueText),
      valueText,
      shortText: x => compact(valueText(x)),
      parse: s => readNumber(n, s)->Option.map(x => clamp(ofPlain(Math.max(lo, Math.min(hi, x))))),
      unit: switch (law, n.unit) {
      | (Exp, _) | (_, Some("%")) => None
      | (_, unit) => unit
      },
    }
  | Choice({names, init, ?short}) =>
    let last = Int.toFloat(Array.length(names) - 1)
    let clamp = x => Float.isFinite(x) ? Math.max(0., Math.min(last, Math.round(x))) : Int.toFloat(init)
    let valueText = x => names[Float.toInt(clamp(x))]->Option.getOr("")
    {
      id,
      index,
      name,
      isInt: true,
      hidden,
      names: Some(names),
      shortNames: short,
      init: Int.toFloat(init),
      min: 0.,
      max: last,
      bipolar: false,
      clamp,
      toNorm: x => last > 0. ? x / last : 0.,
      fromNorm: v => Math.round(v * last),
      plain: x => x,
      ofPlain: x => x,
      longText: withName(valueText),
      valueText,
      shortText: x =>
        switch short {
        | Some(short) => short[Float.toInt(clamp(x))]->Option.getOr("")
        | None => valueText(x)
        },
      parse: s =>
        switch nameIndex(names, s) {
        | Some(i) => Some(i)
        | None =>
          let x = Float.parseFloat(s)
          Float.isFinite(x) ? Some(clamp(x)) : None
        },
      unit: None,
    }
  | Toggle({init}) =>
    let names = ["off", "on"]
    let clamp = x => Float.isFinite(x) ? x >= 0.5 ? 1. : 0. : init ? 1. : 0.
    let valueText = x => clamp(x) != 0. ? "on" : "off"
    {
      id,
      index,
      name,
      isInt: true,
      hidden,
      names: Some(names),
      shortNames: None,
      init: init ? 1. : 0.,
      min: 0.,
      max: 1.,
      bipolar: false,
      clamp,
      toNorm: x => clamp(x),
      fromNorm: v => v >= 0.5 ? 1. : 0.,
      plain: clamp,
      ofPlain: clamp,
      longText: withName(valueText),
      valueText,
      shortText: valueText,
      parse: s => nameIndex(names, s),
      unit: None,
    }
  }
}

let makeAll = specs => specs->Array.mapWithIndex((spec, i) => make(i, spec))

//==============================================================================
// Spec shorthands, for writing a parameter list

let number = (id, name, ~min, ~max, ~init, ~law=?, ~unit=?, ~digits=?, ~text=?, ~hidden=?) => {
  id,
  name,
  kind: Number({min, max, init, ?law, ?unit, ?digits, ?text}),
  ?hidden,
}

// a frequency, time or rate on a log scale
let logarithmic = (id, name, ~min, ~max, ~init, ~unit=?, ~digits=?, ~text=?, ~hidden=?) =>
  number(id, name, ~min, ~max, ~init, ~law=Exp, ~unit?, ~digits?, ~text?, ~hidden?)

// a 0..1 amount shown as a percentage
let percent = (id, name, ~init, ~min=0., ~hidden=?) =>
  number(id, name, ~min, ~max=1., ~init, ~unit="%", ~hidden?)

let choice = (id, name, names, ~init=0, ~short=?, ~hidden=?) => {
  id,
  name,
  kind: Choice({names, init, ?short}),
  ?hidden,
}

let toggle = (id, name, ~init=false, ~hidden=?) => {id, name, kind: Toggle({init: init}), ?hidden}
