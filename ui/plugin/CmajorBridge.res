// Typed bindings to this patch's own endpoints (dsp/Plugin.cmajor), on top of the generic ones in
// PatchConnection.res. Each listener is PatchConnection's addEndpointListener with the endpoint's
// name fixed by @as and its value typed as the patch declares it, so the bindings compile to plain
// method calls with nothing to decode: a Cmajor array arrives as a JS array, a struct as an object
// with its members' names.

open PatchConnection

// fresnel::Telemetry, member for member (dsp/FresnelDisperser.cmajor)
type telemetry = {
  // the input level the envelope follower has: 0 (-54 dB or less) .. 1 (0 dB)
  envelope: float,
  // the slit's width after the envelope, 0..1
  aperture: float,
  // the peak group delay the sections realise, ms (after the budget limit)
  spread: float,
  // the frequency slowed the most
  peakHz: float,
  // the share of the allpass sections dispersing (the rest are parked above topHz)
  budget: float,
  topHz: float,
}

// float[curvePoints]: group delay (ms) at Optics.curveHz(0 .. curvePoints - 1)
type curve = array<float>

@send
external addCurveListener: (t, @as("phaseResponseCurve") _, curve => unit) => unit =
  "addEndpointListener"
@send
external removeCurveListener: (t, @as("phaseResponseCurve") _, curve => unit) => unit =
  "removeEndpointListener"
@send
external addTelemetryListener: (t, @as("telemetry") _, telemetry => unit) => unit =
  "addEndpointListener"
@send
external removeTelemetryListener: (t, @as("telemetry") _, telemetry => unit) => unit =
  "removeEndpointListener"

// Calls f with every curve the patch sends (one of the wrong length, from a mismatched build, is
// dropped); returns a function that stops.
let onCurve = (pc, f) => {
  let listener = (curve: curve) =>
    if Array.isArray(curve) && Array.length(curve) == Optics.curvePoints {
      f(curve)
    }
  pc->addCurveListener(listener)
  () => pc->removeCurveListener(listener)
}

// Calls f with every telemetry message; returns a function that stops.
let onTelemetry = (pc, f) => {
  let listener = (t: telemetry) =>
    if Float.isFinite(t.spread) {
      f(t)
    }
  pc->addTelemetryListener(listener)
  () => pc->removeTelemetryListener(listener)
}
