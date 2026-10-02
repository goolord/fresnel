# The Fresnel disperser

How `dsp/FresnelDisperser.cmajor` turns Fresnel diffraction into an audio effect, how its group
delay is approximated, and how it keeps the phase continuous while every control moves. The numbers
quoted here come from `node tools/test/dispersion.mjs` (part of `just test`), which renders impulse
responses and measures them.

## 1. From Fresnel diffraction to a chirp filter

In optics, a field `U(x', 0)` propagating a distance `z` with wavenumber `k = 2π/λ` is, in the
near (Fresnel) field,

    U(x, z) = e^{ikz} / (iλz) ∫ U(x', 0) exp( i k/(2z) (x − x')² ) dx'

a convolution with a quadratic-phase kernel. In the frequency domain that is a multiplication by a
quadratic phase, `H(ω) = exp(−iγω²)`, whose **group delay** `τ_g(ω) = −dφ/dω = 2γω` grows linearly
with frequency. Played as audio, an impulse through `H` becomes a chirp: the spectrum arrives spread
out in time, each frequency at its own delay. Larger `z` means larger `γ`, a longer chirp.

### The phase law the plugin uses

A literal `γω²` over the whole linear frequency axis puts nearly all of its delay in the top octaves
and almost none below 1 kHz, and it can only make highs lag. The plugin writes the same law on a
warped axis and adds the cubic (third-order) term, as in ultrafast optics, where a pulse's spectral
phase is expanded as `φ = ½·GDD·Δω² + ⅙·TOD·Δω³`:

- **Axis.** `u(f) = ln(1 + f/200 Hz) / ln(1 + f_top/200 Hz)`, 0 at DC and 1 at `f_top` (16 kHz, or
  0.4 of the sample rate if that is lower). It's linear below about 200 Hz and logarithmic above,
  like the mel scale, so every octave above the knee gets a fair share.
- **Phase.** `θ(u) = γu² + δu³` (plus a linear term, which is a constant delay). Its group delay is
  a parabola in `u`:

      τ(u) = T · max(0, 1 − ((u − c)/h)²)

  with `γ = T·c/h²` and `δ = −T/(3h²)`. The three numbers are the controls:

  | control | symbol | meaning |
  |---|---|---|
  | Distance | `T` (`z`) | the peak group delay (0–250 ms): how far the light has travelled |
  | Chroma | `c` (`λ`) | where the parabola peaks: which colour is slowed most, red (lows lag, `c → 0`, *anomalous* dispersion) to violet (highs lag, `c → 1`, *normal* dispersion, as in glass) |
  | Aperture | `h` | the parabola's half-width, as a share of the distance from `c` to the far end of the axis: how wide a band is dispersed |

  At Chroma = +1 and Aperture = 100 % the shape is `T(2u − u²)`, the Fresnel chirp (highs lag)
  bending over at the top. At Chroma = −1 it's the mirror image, a spring-like downward chirp.

- **Slit (the soft mask).** `max(0, ·)` is the slit's edge: outside `[c − h, c + h]` the group delay
  is zero and the sound passes straight through. In optics a slit's Fresnel number
  `N_F = a²/(λz)` decides between a crisp geometric shadow (large `N_F`) and a broad diffraction
  pattern (small `N_F`), so narrowing the slit concentrates the dispersion into a narrower,
  longer-ringing band. The wavefront display draws each frequency as a slit's Fresnel diffraction
  pattern at an `N_F` that falls with the aperture, the frequency (a longer wave) and the distance.

- **Intensity.** An envelope follower (3 ms attack, 150 ms release, stereo linked) reads the input
  level from −54 dB to 0 dB as 0..1. The slit width actually used is
  `aperture · 8^(−intensity · envelope)`, between 3 % and 100 %, so with Intensity above 0 loud
  passages narrow the slit and focus the dispersion (a Kerr-like, intensity-dependent effect), and
  below 0 they widen it.

## 2. Why a time-domain allpass cascade, and not an STFT

The brief offered two routes: a frequency-domain STFT that multiplies each frame by the phase law,
or a time-domain cascade of allpass sections. The plugin uses the cascade only:

- **Zero latency.** The cascade is causal and adds no block delay (`processor.latency` is 0). An
  STFT needs a whole frame (1024–2048 samples, 21–43 ms at 48 kHz) of latency.
- **No circular wrap.** Multiplying an N-point frame by a phase whose group delay exceeds about N/2
  samples doesn't delay the sound: it wraps around inside the frame (time aliasing) and smears into
  pre-echo. N = 2048 at 48 kHz holds about 21 ms. The controls go to 250 ms, which would need frames
  of 32768 samples or more, with that much latency and frame-boundary modulation.
- **Continuous modulation.** An STFT applies a new phase per hop, so a moving control steps every
  256 samples, and overlap-add of differently phased frames partly cancels. The cascade's
  coefficients glide every sample (section 5).
- **Cost.** The cascade costs `sections` second-order lattices per sample, fixed, about 6 % of one
  core at 48 kHz stereo (384 sections, float64), measured by rendering 30 s of noise.

## 3. Approximating the group delay with allpass sections

### The phase budget

A real second-order allpass section adds exactly `2π` of phase between DC and Nyquist, so its group
delay integrates to `2π` over `[0, π]`. A cascade of `M` sections integrates to `2πM`: the sections
are a **phase budget**, and the target's cumulative phase

    Φ(ω) = ∫₀^ω τ(ω') dω'

is what they must spend. For the plugin's `M = 384`, `2πM ≈ 2413` rad·samples. Dispersing highs
costs much more than dispersing lows (the band `[0, ω]` is wider), so how far a setting can go
depends on its shape:

| setting | budget used | spread realised |
|---|---|---|
| violet, full width, 14 ms | 52 % | 98 % |
| violet, full width, 30 ms | 89 % | 77 % (limited) |
| red, full width, 20 ms | 29 % | 100 % |
| red, half width, 80 ms | 24 % | 100 % |
| narrow slit at 500 Hz, 180 ms | 18 % | 100 % |

### Placing the poles

The poles are placed after Abel & Smith ("Robust design of very high-order allpass dispersion
filters", DAFx 2006). Every design step:

1. Evaluate `τ` on a grid of 513 points uniform in `u` (dense where the bands are narrow, at low
   frequencies) and integrate it (trapezoids) into `Φ`. A floor of 0.02 samples keeps `Φ` strictly
   increasing, so it can be inverted.
2. Section `k` owns the band where `Φ` runs from `2πk` to `2π(k+1)`. Its pole angle `θ_k` is where
   `Φ = 2π(k + ½)`, found by walking the grid (the targets rise, so one pass serves every section).
3. Its radius comes from its band's width `Δ_k`: `ρ_k = exp(−β·Δ_k/2)`, with `β = 1.4`, and
   `Δ_k = min(band edges' distance, 2π/τ(θ_k))`. The local density rule matters for the first
   section, whose band starts at DC and can stretch across flat ground: without it that section
   becomes a broad, low-Q pole adding a sample of delay everywhere.
4. Reflection coefficients for the lattice (section 4).

A pole pair's group delay is close to a Lorentzian of half-width about `1 − ρ`, and its area is
fixed at `2π`, so evenly spaced Lorentzians sum to a smooth curve with a ripple of about
`2·e^{−πβ}`: ±2.5 % at `β = 1.4`. A larger `β` smooths more but blurs detail. 1.4 measured best
across the test settings (1.2 to 1.7 were tried).

### The resolution limit

One section covers a band of `2π/τ` radians, so **the cascade can't draw detail in the group delay
finer than `2π/τ`**. That's the time–frequency uncertainty, and the allpass version of an optical
diffraction limit. It shows where the target has a corner (the slit's edges) or where the delay is
small but rising (the bottom of the violet chirp: at 50 Hz the target is 1.4 ms, the realised 2.9
ms, because a single section spans 0–700 Hz there). The view draws both curves, so the user can see
this.

### Parking the unused sections

With a fixed `M`, the phase the dispersion doesn't need still has to go somewhere. Turning sections
off would make discontinuities, and turning them into flat delays (`ρ = 0`, `z⁻²`) would move the
whole signal by up to `2M` samples as the controls change, which is audible Doppler. Instead the
target is extended above `f_top` with a constant group delay that soaks up the rest of the budget:

    τ_park = (2πM − Φ(ω_top)) / (π − ω_top)

so the sections not dispersing are **parked** between 16 kHz and Nyquist. Parked sections are made
narrow (`β` ramps from 1.4 to 0.05 just above `ω_top`, `ρ ≤ 0.99995`) so that their skirts don't
reach back into the audible band. As a result:

- where the target is zero, the wet signal has (nearly) zero group delay: there's no bulk delay to
  compensate, and switching the dispersion on or off doesn't move the rest of the spectrum in time.
  At rest the phase is −0.7° at 1 kHz, −3.8° at 5 kHz and −9.7° at 10 kHz (measured);
- every section is always in use, and as the controls move, sections slide between the audible band
  and the parking band.

### Phase on either side of the band

Each section turns the phase by exactly one turn, so the cascade can only realise **whole turns**:
the fraction of a turn the target asks for beyond its last whole one stays with a parked section.
Far above the dispersed band the phase therefore comes back to a whole number of turns, which means
zero, whatever the setting. (Measured with the band at 1–2 kHz, sweeping Distance from 18 to 21 ms,
the phase at 10 kHz stays between 25° and 34° rather than turning round.) Near the band it doesn't:
a pole's phase approaches its full turn only as `2w/d` (width `w`, distance `d`), so the band's
poles leave a phase tail on both sides that falls off roughly as `1/d`. In the same setting: −88°
at 500 Hz, +91° at 5 kHz, +25° at 10 kHz. This is the Hilbert-transform side of a group delay
confined to a band: a narrower pole (smaller `β`) shortens the tails but makes the curve ripple
more.

This matters only when the wet signal is summed with the dry one (section 5, item 6).

### The budget limit

When a setting asks for more phase than the sections hold, `T` is scaled down by a soft minimum
rather than clipped:

    Φ_used = Φ_wanted · (1 + (Φ_wanted / room)⁴)^(−1/4),    room = 2πM − parked minimum

so the realised spread saturates smoothly as Distance turns up. The telemetry reports the realised
spread and the share of the budget in use ("% of the glass" in the view).

### Measured accuracy (48 kHz)

Group delay in ms, measured from the rendered impulse response / target:

| setting | 100 Hz | 500 Hz | 1 kHz | 2 kHz | 5 kHz | 10 kHz |
|---|---|---|---|---|---|---|
| violet wide (14 ms) | 3.15 / 2.46 | 6.36 / 6.84 | 8.66 / 9.09 | 10.66 / 11.11 | 12.90 / 13.06 | 13.58 / 13.84 |
| red wide (20 ms) | 19.34 / 19.90 | 18.72 / 18.55 | 17.26 / 16.89 | 13.87 / 14.26 | 9.33 / 9.18 | 4.13 / 4.07 |
| red long (80 ms) | 79.62 / 79.69 | 66.98 / 68.69 | 45.66 / 45.71 | 4.10 / 5.04 | 0.05 / 0 | 0.01 / 0 |
| laser (180 ms, narrow) | 0.84 / 0 | 171.83 / 173.16 | 3.00 / 0 | 0.10 / 0 | 0.02 / 0 | 0.01 / 0 |

The magnitude stays flat within 0.001 dB at every setting (it's an allpass), and the curve the
plugin sends the view (`phaseResponseCurve`) agrees with the measurement at its own frequencies. The
script checks both (at 48 kHz in `just test`; `--rate=44100` or `--rate=96000` give the same
results, since the section count doesn't depend on the sample rate: the phase budget is a
time–bandwidth product).

## 4. The lattice

Each section is the allpass `(ρ² − 2ρcosθ z⁻¹ + z⁻²) / (1 − 2ρcosθ z⁻¹ + ρ² z⁻²)`, realised as a
two-stage **normalized (rotation) lattice** in float64. With `s₀` and `s₁` the stages' states (`g₀`
and `g₁` a sample ago):

    f₁ =  c₂·x − k₂·s₁          y   = k₂·x + c₂·s₁
    f₀ =  c₁·f₁ − k₁·s₀         s₁' = k₁·f₁ + c₁·s₀          s₀' = f₀

with reflection coefficients `k₂ = ρ²`, `k₁ = −2ρcosθ/(1 + ρ²)` and their complements
`c = √(1 − k²)`. Each stage is a plane rotation by `(k, c)`, which preserves energy.

**Accuracy near the unit circle.** Parked poles and long low-frequency delays have `ρ` within
`5·10⁻⁵` of 1 and `|k₁|` within `10⁻⁷` of 1. Computing `c₁` as `√(1 − k₁²)` would lose nearly all
its digits, so it's computed from the half angle:

    c₁ = √( ((1−ρ)² + 4ρ·sin²(θ/2)) · ((1−ρ)² + 4ρ·cos²(θ/2)) ) / (1 + ρ²)

Both factors are sums of non-negative terms, with no cancellation. The states and coefficients are
float64: a parked pole at `ρ = 0.99995` has `1 − k₁ ≈ 10⁻⁹`, which float32 rounds to exactly 1,
putting the pole on the unit circle.

## 5. Avoiding phase discontinuities while the controls move

A dispersion filter is the worst case for modulation: hundreds of high-Q poles, a phase response
that wraps hundreds of times, and controls (and an envelope) that move it all the time. Each of the
following prevents a different kind of click.

1. **Continuous pole trajectories.** The section count never changes and section `k` always owns
   the `k`-th `2π` of the cumulative phase, so a small change in the controls moves every pole a
   small distance. Sections are never switched in or out: parking replaces that (section 3).
   *Don't* re-sort poles, pick the section count from the setting, or let a section jump to another
   band. One section at a time is in transit: the one holding the target's last, partial turn waits
   parked until the target needs half of it, then crosses the empty spectrum between the band and
   16 kHz quickly (the target there is only the 0.02-sample floor). While it crosses, its band is
   wide, so it's broad and low-Q and barely moves the phase.
2. **Smooth controls.** Distance (`T`), Chroma (`c`) and the slit (`h`, which includes the envelope)
   pass through 40 ms one-pole smoothers before each design. The envelope itself is smoothed by its
   attack and release.
3. **Glides every sample.** The poles are redesigned every 64 frames, and each section's four
   coefficients `(k₁, c₁, k₂, c₂)` glide in a straight line from where they are to the new design over
   the next 64 frames. Each glide starts from the current values, not the previous target, so
   rounding never accumulates.
4. **Passive in-between filters.** A pair `(k, c)` with `k² + c² = 1` makes each stage a rotation.
   A straight line between two such points (`c ≥ 0`, the right half of the unit circle) is a chord,
   which lies inside the circle, so every in-between pair has `k² + c² ≤ 1` and each stage is a
   *contraction*. The time-varying cascade can only lose energy, never gain it, however fast the
   coefficients move. This is why the normalized lattice was chosen over direct form (where
   interpolated coefficients give in-between filters with transient gain) and over the
   two-multiplier lattice (stable, but not energy-bounded under modulation).
5. **No bulk delay moves.** Because unused phase is parked above 16 kHz rather than held in flat
   delays, the arrival time of everything outside the dispersed band stays at zero while the
   controls move: there's no Doppler pitch shift on sweeps.
6. **Mixing without combs.** In the default **morph** blend, Mix scales the dispersion itself
   (`T·mix`) and the output is all wet, so there's never a sum of two differently phased signals
   and never a comb. **Crossfade** sums dry and wet. Inside the dispersed band they differ by
   design, which gives the phaser-like notches some people want. Around it, the poles' phase tails
   (section 3) colour the sum, fading with distance from the band. Far from it the two line up, with
   no bulk delay and a whole number of turns. Mix and output gain glide per sample (20 ms).
7. **Resting and guards.** After 1.5 s of input below −180 dB the lattice clears its states and
   stops computing (and its coefficients jump straight to each design), so float64 states never
   decay into denormals. A guard clears the states if their energy ever exceeds `10⁶`. The stress
   test (`tools/test/dsp/Fresnel.cmajor`) sweeps every control far faster than anyone would, with
   the intensity at ±100 %, and checks the output stays finite and bounded.

**Measured.** `dispersion.mjs` plays a 220 Hz tone while Distance sweeps from 5 to 40 ms in 6 s,
with the tone inside the dispersed band, and measures the energy above 2 kHz against the tone (per
2048-point frame). Anything there is the coefficients' movement leaking out. It comes to −73 dB
(median) and −62 dB (worst frame), and the test fails above −50 dB. The tone itself bends slightly
in pitch while its group delay changes (about 0.6 %, the same as a moving delay line), which is the
effect, not an artefact.

## 6. What the view receives

| endpoint | type | rate | contents |
|---|---|---|---|
| `phaseResponseCurve` | `float[256]` | ≈ 23 Hz at 48 kHz | group delay (ms) of the placed sections at 256 frequencies, 20 Hz–20 kHz on a log scale, worked out from the poles 8 frequencies per design step |
| `telemetry` | `fresnel::Telemetry` | with each curve | envelope (0..1), aperture after the envelope, realised spread (ms), peak frequency, budget share, `f_top` |
| `meterOut` | `float<2>` | ≈ 30 Hz | output peak levels |

`ui/plugin/CmajorBridge.res` binds these as typed `@send` externals (the endpoint name fixed with
`@as`), so a curve arrives as `array<float>` and the telemetry as a record, with no decoding.
`ui/plugin/DiffractionCanvas.res` draws them, and falls back to the target curve worked out from the
parameters (`ui/plugin/Optics.res`, which mirrors the DSP's axis and shape) when the patch is
silent, as in the UI preview.

## 7. Differences from the original brief

- **`bsconfig.json` → `rescript.json`; `@mel.send`/`@mel.get` → `@send`/`@get`.** The project is
  ReScript 12 (where `bsconfig.json` is the deprecated name of `rescript.json`). The `@mel.*`
  attributes are Melange's, the OCaml-to-JS compiler that forked from ReScript, and ReScript doesn't
  accept them. Its own `@send`/`@get` externals are the zero-cost equivalents.
- **No STFT path**, for the reasons in section 2: at the delays the controls reach it would need
  latency and frame sizes the cascade avoids.
- **Files.** `FresnelApp.res` is the page, `DiffractionCanvas.res` the wavefront and slit drawings,
  `CmajorBridge.res` the typed endpoint bindings, `Optics.res` the shared optics. They sit in
  `ui/plugin/` beside the template's shell, which provides the controls, presets and host plumbing.
