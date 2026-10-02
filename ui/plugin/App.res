// The plugin's view: its pages, and what else it gives the shell (Shell.res). Index.res mounts it.

let pages: array<Shell.page> = [
  {
    id: "main",
    label: "Fresnel",
    title: "The wavefront and the lens",
    hint: FresnelApp.hint,
    build: FresnelApp.build,
  },
]

let mount = pc => {
  PresetFormat.register(Formats.all)
  Shell.mount(pc, ~specs=Params.all, ~pages)
}
