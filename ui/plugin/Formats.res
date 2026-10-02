// The preset file formats the plugin reads, its own first (PresetFormat.res). Add a format here to
// load another plugin's presets or banks: the Load button, drag and drop, the browser and the
// factory presets (presets/) all take any format listed.

let all = [PresetFormat.jsonFormat(~name="Fresnel preset", ~extension=".preset")]
