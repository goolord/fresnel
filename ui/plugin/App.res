// The plugin's view: its pages, and what else it gives the shell (Shell.res). Index.res mounts it.

// (the preset formats register themselves)
let formats = Formats.all

let pages: array<Shell.page> = [
  {
    id: "main",
    label: "Fresnel",
    title: "The wavefront and the lens",
    hint: FresnelApp.hint,
    build: FresnelApp.build,
  },
]

let mount = pc => Shell.mount(pc, ~specs=Params.all, ~pages)
