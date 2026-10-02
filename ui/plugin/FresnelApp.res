// The plugin's page: the wavefront (DiffractionCanvas) on the left, and on the right the lens's
// controls, the slit the envelope moves, and the output level.

let hint = "Distance spreads the arrival times, Chroma picks the colour slowed most, Aperture how wide a band; hover the wavefront to read a frequency's delay."

let build = (ctx: Ctx.t, page) => {
  let margin = 6.
  let height = Style.pageHeight - 2. * margin
  let meterWidth = 84.
  let cw = 86.
  let controlsWidth = 3. * cw - Grid.columnGap + 2. * Grid.padX + 2.
  let waveWidth = Style.designWidth - 2. * margin - controlsWidth - meterWidth - 2. * Grid.gap

  // the patch's curve and telemetry, shared by the drawings
  let live = DiffractionCanvas.listen(ctx)

  let wave = Panel.make(page, ~title="wavefront", ~x=margin, ~y=margin, ~w=waveWidth, ~h=height)
  DiffractionCanvas.make(ctx, wave.el, {x: 8., y: 27., w: waveWidth - 16., h: height - 35.}, ~live)->ignore

  // big knobs: four rows each
  let lens = Panel.make(page, ~title="lens", ~x=Panel.right(wave), ~y=margin, ~w=controlsWidth, ~h=Grid.panelHeight(9))
  let g = Grid.make(ctx, lens.el, ~cw)
  g->Grid.knob("distance", 0, 0, "distance", ~rows=4)
  g->Grid.knob("chroma", 1, 0, "chroma", ~rows=4)
  g->Grid.knob("aperture", 2, 0, "aperture", ~rows=4)
  g->Grid.knob("intensity", 0, 4, "intensity", ~rows=4)
  g->Grid.knob("mix", 1, 4, "mix", ~rows=4)
  g->Grid.knob("level", 2, 4, "output", ~rows=4)
  g->Grid.choice("blend", 0, 8, "blend", ~span=3)

  let slitTop = Panel.bottom(lens)
  let slitHeight = height + margin - slitTop
  let slit = Panel.make(page, ~title="slit", ~x=lens.x, ~y=slitTop, ~w=controlsWidth, ~h=slitHeight)
  DiffractionCanvas.slit(ctx, slit.el, {x: 8., y: 27., w: controlsWidth - 16., h: slitHeight - 35.}, ~live)->ignore

  let out = Panel.make(page, ~title="out", ~x=Panel.right(lens), ~y=margin, ~w=meterWidth, ~h=height)
  let mw = 34.
  Meter.make(ctx, out.el, {x: (meterWidth - mw) / 2., y: 27., w: mw, h: height - 37.}, ~endpoint="meterOut", ~name="Output")->ignore
}
