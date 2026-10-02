# Builds the CLAP plugin on macOS, Linux and Windows.
#
#   just            build dist/<name>.clap for this machine
#   just install    build, then copy it into the CLAP folder (on Windows, the system one, which
#                   asks for administrator rights)
#   just play       run the patch in Cmajor's player, with its view in a browser
#   just preview    serve the view with a stand-in patch (tools/ui-preview), for working on the UI
#   just test       render the DSP tests (tools/test/dsp) and measure the dispersion
#   just rename "My Plugin" com.me.myplugin   give the template its own name and IDs
#
# The plugin's name comes from the manifest, plugin.cmajorpatch. Build on each OS natively; there
# is no cross-compiling. Requirements:
#   all:      cmaj (Cmajor CLI), node and npm, git, cmake >= 3.16 and a C++17 compiler
#   Windows:  Visual Studio 2022 with the C++ workload (CMake's default generator)
#   macOS:    Xcode command line tools; the result is a universal arm64/x86_64 bundle
#   Linux:    pkg-config, gtk3 and webkit2gtk dev packages (see `just linux-deps`)
#
# Every recipe line is a plain command (file operations go through `cmake -E`), so the same
# recipes run under sh and PowerShell; only installing differs per OS.

set windows-shell := ["powershell.exe", "-NoLogo", "-NoProfile", "-Command"]

cmaj         := env("CMAJ", "cmaj")
config       := env("CONFIG", "Release")
clap_version := env("CLAP_VERSION", "1.2.10")

root      := justfile_directory()
patch     := root / "plugin.cmajorpatch"
name      := `node tools/manifest.mjs name`
build     := root / "build"
clap_dir  := build / "deps" / ("clap-" + clap_version)
project   := build / "clap-project"
staging   := build / "clap-project-new"
cmake_dir := build / "cmake"
out_dir   := build / "out"
dist      := root / "dist"

plugin := name + ".clap"

# What CMake calls the build: Cmajor's generator names the target after the manifest's name with
# everything but letters, digits and underscores removed ("My Plugin" builds MyPlugin.clap), so
# dist/ gets the display name and build/out/ the target's.
built := replace_regex(name, "[^A-Za-z0-9_]", "") + ".clap"

# Where to install on each OS. Windows hosts don't all scan the per-user CLAP folder, so it goes
# in the system-wide one (CommonProgramW6432 is the 64-bit Common Files, even if a 32-bit process
# launched just).
install_dir := if os() == "windows" {
    env("CommonProgramW6432", env("CommonProgramFiles", "C:\\Program Files\\Common Files")) / "CLAP"
} else if os() == "macos" {
    home_directory() / "Library" / "Audio" / "Plug-Ins" / "CLAP"
} else {
    home_directory() / ".clap"
}

# macOS builds a .clap bundle (a folder); elsewhere it is a single shared library.
copy := if os() == "macos" { "copy_directory" } else { "copy" }

# Build the plugin into dist/
default: package

# Install the view's build tools (esbuild, ReScript)
deps:
    npm install

# Compile the ReScript interface and bundle it, with the factory presets, into bundle/
ui:
    {{ if path_exists(root / "node_modules" / "rescript") == "true" { "cmake -E echo \"node modules present\"" } else { "npm install" } }}
    npm run build

# Regenerate dsp/Params.cmajor and the manifest's source list from ui/plugin/Params.res
gen: ui
    node "{{ root / "tools" / "gen.mjs" }}"

# Fetch the CLAP headers (once per CLAP_VERSION)
clap:
    {{ if path_exists(clap_dir / "include" / "clap" / "clap.h") == "true" { "cmake -E echo \"CLAP " + clap_version + " headers present\"" } else { "git clone --depth 1 --branch " + clap_version + " https://github.com/free-audio/clap \"" + clap_dir + "\"" } }}

# (in a staging folder; only files that changed are copied into the project, so an unchanged
# entry.cpp keeps its timestamp and isn't recompiled)
# Generate the CLAP C++/CMake project from the patch and patch its wrapper (tools/clap-patch.mjs)
generate: gen clap
    cmake -E rm -rf "{{ staging }}"
    {{ cmaj }} generate --target=clap "--clapIncludePath={{ clap_dir / "include" }}" "--output={{ staging }}" "{{ patch }}"
    node "{{ root / "tools" / "clap-patch.mjs" }}" "{{ staging }}"
    node "{{ root / "tools" / "sync-dir.mjs" }}" "{{ staging }}" "{{ project }}"
    cmake -E rm -rf "{{ staging }}"

# Configure and compile the generated project
compile: generate
    cmake -S "{{ project }}" -B "{{ cmake_dir }}" --no-warn-unused-cli "-DCMAKE_BUILD_TYPE={{ config }}" "-DCLAP_INCLUDE_PATH={{ clap_dir / "include" }}" "-DCMAKE_LIBRARY_OUTPUT_DIRECTORY_{{ uppercase(config) }}={{ out_dir }}"
    cmake --build "{{ cmake_dir }}" --config {{ config }} --parallel

# Copy the built plugin to dist/
package: compile
    cmake -E rm -rf "{{ dist / plugin }}"
    cmake -E make_directory "{{ dist }}"
    cmake -E {{ copy }} "{{ out_dir / built }}" "{{ dist / plugin }}"
    cmake -E echo "built {{ dist / plugin }}"

# Build, then install into the user's CLAP folder
[unix]
install: package
    cmake -E make_directory "{{ install_dir }}"
    cmake -E rm -rf "{{ install_dir / plugin }}"
    cmake -E {{ copy }} "{{ dist / plugin }}" "{{ install_dir / plugin }}"
    cmake -E echo "installed {{ install_dir / plugin }}"

# (Program Files needs administrator rights, so only the copy runs elevated: a UAC prompt,
# unless the shell already is)
# Build, then install into the system CLAP folder
[windows]
install: package
    $p = Start-Process cmake -Verb RunAs -Wait -PassThru -WindowStyle Hidden -ArgumentList '-E copy "{{ dist / plugin }}" "{{ install_dir / plugin }}"'; if ($p.ExitCode) { throw "couldn't copy to {{ install_dir }}; is a host holding the plugin open?" }
    cmake -E echo "installed {{ install_dir / plugin }}"

# Remove the plugin from the user's CLAP folder
[unix]
uninstall:
    cmake -E rm -rf "{{ install_dir / plugin }}"

# Remove the plugin from the system CLAP folder (elevated, as for install)
[windows]
uninstall:
    $p = Start-Process cmake -Verb RunAs -Wait -PassThru -WindowStyle Hidden -ArgumentList '-E rm -f "{{ install_dir / plugin }}"'; exit $p.ExitCode

# (it rebuilds when a source changes; rerun `just gen` after changing the parameters, and
# `just ui` after changing the view)
# Run the patch in Cmajor's player
play: gen
    {{ cmaj }} play "{{ patch }}"

# Serve the view with a stand-in patch: open http://localhost:8123/tools/ui-preview/
preview: ui
    node "{{ root / "tools" / "ui-preview" / "serve.mjs" }}"

# Render the DSP tests (tools/test/dsp/*.cmajor, a filter picks some), the whole plugin, and the
# disperser's measured group delay against its target (tools/test/dispersion.mjs)
test filter="": gen
    node "{{ root / "tools" / "test" / "dsp.mjs" }}" "{{ filter }}"
    node "{{ root / "tools" / "test" / "plugin.mjs" }}"
    node "{{ root / "tools" / "test" / "dispersion.mjs" }}"

# Give the plugin its own name, ID, manufacturer and codes (see tools/rename.mjs)
rename plugin_name id manufacturer="":
    node "{{ root / "tools" / "rename.mjs" }}" "{{ plugin_name }}" "{{ id }}" "{{ manufacturer }}"

# Install the Linux build dependencies (Debian/Ubuntu)
[linux]
linux-deps:
    sudo apt-get install -y build-essential cmake git pkg-config libgtk-3-dev libwebkit2gtk-4.1-dev

# Delete build/, dist/ and the compiled interface
clean:
    cmake -E rm -rf "{{ build }}" "{{ dist }}" "{{ root / "bundle" }}"
    npx rescript clean
