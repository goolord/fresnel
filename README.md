# Fresnel

A CLAP dispersion effect after Fresnel diffraction: every frequency arrives at its own time, so hits
turn into chirps, from a glassy shimmer to a spring-tank drip or a laser zap. It has zero latency
and is drawn as light.

- **Distance**: how far apart the arrivals spread (0–250 ms)
- **Chroma**: which frequency is slowed most, red (lows) to violet (highs)
- **Aperture**: how wide a band gets dispersed
- **Intensity**: how much the input level narrows (or widens) that band
- **Mix** / **Blend**: *morph* scales the effect, *crossfade* blends with the dry sound

Under the hood it's a 384-section allpass cascade in Cmajor with a ReScript UI. The details are in
[docs/dispersion.md](docs/dispersion.md).

## Building

Needs cmaj, node, just, cmake and a C++17 compiler.

```
just              build dist/Fresnel.clap
just install      build and copy to the CLAP folder
just play         run in the Cmajor player
just preview      UI in a browser at localhost:8123/tools/ui-preview/
just test         DSP tests and dispersion measurements
```
