// The plugin's settings for the view: what the header calls it, the size it's designed at, its
// themes, and the categories presets can have. (Its name, ID and the rest are in the manifest,
// plugin.cmajorpatch; `just rename` changes them all.)

// the name in the header
let brand = "fresnel"

// The size the pages are laid out at, in design pixels. The window scales the whole stage, keeping
// this aspect ratio; tools/gen.mjs copies it into the manifest's view size.
let designWidth = 1000.
let designHeight = 560.

// The themes the settings dialog offers, the first being the default (see Theme.res).
let themes = [Theme.night, Theme.oat, Theme.paper]

// The categories the info dialog suggests (any other may be typed).
let categories = ["bass", "lead", "pad", "keys", "drums", "delay", "reverb", "filter", "distortion", "dynamics", "other"]
