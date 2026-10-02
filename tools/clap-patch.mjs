// Patches the CLAP wrapper that `cmaj generate --target=clap` writes, for things Cmajor's wrapper
// doesn't do:
//
//  - Resizing keeps the interface's aspect ratio (resize hints and adjust_size), so the host
//    window scales the whole panel instead of leaving bars around it, at any DPI.
//  - The interface size ("zoom") is a user setting, kept in a settings file that every instance
//    shares: %APPDATA%<name>settings.json, ~/Library/Application Support/<name> or
//    ~/.config/<name>, <name> being the manifest's. New editor windows open at that size, and an
//    instance keeps its own size while its editor is closed.
//  - The view reaches the settings through stored-state requests whose key starts with
//    "bridge:settings?" (?get, ?zoom=<factor>, ?save=<json>). The patch answers every request by
//    broadcasting it to its views; a listener view added here acts on them and replies to the
//    editor with a "bridge:settings" state value { settings: <the file's object>, zoom: <this
//    window's size> }. Nothing is stored in the plugin's state. See ui/core/Settings.res. The code
//    is in tools/clap/Bridge.h, which is copied next to the wrapper.
//  - The bank library: the preset browser's folders, scanned and cached, and the files opened in
//    it, kept in <settings folder>/banks. The view asks with keys that start with
//    "bridge:library?" and the plugin answers with "bridge:library" values; see
//    tools/clap/Library.h and ui/presets/BankLibrary.res.
//  - The host's menu for a parameter (CLAP's context-menu extension; in FL Studio it has Create
//    automation clip, Link to controller and so on), which a double right-click on a control
//    opens. The view asks through the same bridge, with keys that start with "bridge:host?":
//    ?get is answered with a "bridge:host" state value { menu: <whether the host can show it> };
//    ?menu=<json> { id, x, y, scale } shows it for the parameter with that endpoint ID, at a point
//    in the view (CSS pixels, and the view's device pixel ratio); ?dismiss closes it, for a press
//    or Escape in the view, which the menu never hears on Windows. The menu is shown from
//    on_main_thread, once the view's message has been handled. See ui/core/HostMenu.res.
//  - The transport reaches the patch only when it changes: the tempo, the time signature and
//    whether it plays, records and loops (a host sends the whole transport with every call, and
//    with small buffers each event cost more than a small block's DSP). The song position isn't
//    sent; add it back below if your DSP needs it.
//  - A CPU diagnostic, off unless CMAJ_PLUGIN_PERF is set: the process calls of each instance are
//    timed and summarised in <name>-perf.log in the temp folder (tools/clap/Perf.h).
//  - The latency the patch declares (`processor.latency = ...` in the DSP, a number or a `let`
//    constant): Cmajor's C++ generator reports 0 whatever the patch declares.
//
// and to load faster:
//
//  - The patch worker runs in QuickJS, in the plugin, instead of in a hidden web view (with a
//    renderer process) of its own per instance, which takes half a second or more to start.
//    choc's QuickJS never ran promise jobs, so it does now (choc_javascript_QuickJS.h).
//  - Activating rebuilds the patch only if the sample rate or block size changed, instead of
//    loading it again from scratch (which built it three times).
//  - Cmajor's Engine keeps the program details it last parsed (cmaj_Engine.h), which a build
//    asks for several times.
//
//   node tools/clap-patch.mjs [path to the generated project]

import { readFileSync, writeFileSync, copyFileSync, readdirSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const project = process.argv[2] ?? join(root, "build", "clap-project");
const marker = "// clap-patch:";

const manifest = JSON.parse(readFileSync(join(root, "plugin.cmajorpatch"), "utf8"));

// The latency the DSP declares: `processor.latency = <number or constant>;` in one of the plugin's
// own sources (dsp/*.cmajor, not the library), a constant being a `let name = <number>;` there.
const dspSources = readdirSync(join(root, "dsp"))
  .filter((f) => f.endsWith(".cmajor"))
  .map((f) => readFileSync(join(root, "dsp", f), "utf8"))
  .join("\n");
const latencyExpr = /processor\.latency\s*=\s*([A-Za-z0-9_:]+)\s*;/.exec(dspSources)?.[1];
const resolveConstant = (e) =>
  /^\d+$/.test(e)
    ? Number(e)
    : Number(new RegExp(`let\\s+${e.split("::").pop()}\\s*=\\s*(\\d+)\\s*;`).exec(dspSources)?.[1]);
const latency = latencyExpr ? resolveConstant(latencyExpr) : 0;
if (latencyExpr && !Number.isInteger(latency)) throw new Error(`can't work out processor.latency = ${latencyExpr}`);

// the file being patched
let file, source;

// Starts patching a file; false if it already is.
const open = (path) => {
  file = path;
  source = readFileSync(file, "utf8").replace(/\r\n/g, "\n");
  if (!source.includes(marker)) return true;
  console.log(`${file} is already patched`);
  return false;
};

const save = () => {
  writeFileSync(file, source);
  console.log(`patched ${file}`);
};

const fail = (what) => {
  console.error(`clap-patch: couldn't find ${what} in ${file}; the Cmajor wrapper has changed, so update tools/clap-patch.mjs`);
  process.exit(1);
};

// Replaces the one occurrence of `find`.
const replace = (find, replacement) => {
  const at = source.indexOf(find);
  if (at < 0 || source.indexOf(find, at + 1) >= 0) fail(JSON.stringify(find.slice(0, 80)));
  source = source.slice(0, at) + replacement + source.slice(at + find.length);
};

// Inserts text just before or after the one occurrence of `anchor`.
const insertBefore = (anchor, text) => replace(anchor, text + anchor);
const insertAfter = (anchor, text) => replace(anchor, anchor + text);

//==============================================================================
// Cmajor's Engine

if (open(join(project, "include", "cmajor", "API", "cmaj_Engine.h"))) {
  insertAfter(`#include <functional>\n`, `#include <mutex>\n#include <string>\n`);

  replace(
    `                return choc::json::parse (choc::com::StringPtr (details));\n`,
    `                ${marker} a big patch's details take a while to parse, and loading it asks
                // for them several times, so the last ones parsed are kept (added by
                // tools/clap-patch.mjs)
                static std::mutex lock;
                static std::string lastText;
                static choc::value::Value lastDetails;

                choc::com::StringPtr text (details);
                std::lock_guard<std::mutex> lockForCache (lock);

                if (text.get() != lastText)
                {
                    lastDetails = choc::json::parse (text.get());
                    lastText = std::string (text.get());
                }

                return lastDetails;
`,
  );

  save();
}

//==============================================================================
// choc's QuickJS, which runs the patch worker

if (open(join(project, "include", "choc", "choc", "javascript", "choc_javascript_QuickJS.h"))) {
  insertAfter(
    `    void pumpMessageLoop() override {}\n`,
    `
    ${marker} runs the promise jobs (await, then) that a call into the script queued, as an
    // event loop does after each task; without this, async code stopped at its first await
    // (added by tools/clap-patch.mjs)
    void runPendingJobs()
    {
        JSContext* jobContext = nullptr;

        while (JS_ExecutePendingJob (runtime, &jobContext) > 0)
        {}
    }
`,
  );

  replace(
    `        return takeValue (JS_Eval (context, code.c_str(), code.size(), "", JS_EVAL_TYPE_GLOBAL)).toChocValue();\n`,
    `        auto result = takeValue (JS_Eval (context, code.c_str(), code.size(), "", JS_EVAL_TYPE_GLOBAL)).toChocValue();
        runPendingJobs();
        return result;
`,
  );

  for (const type of ["JS_EVAL_TYPE_MODULE", "JS_EVAL_TYPE_GLOBAL"]) {
    const line = `                auto result = takeValue (JS_Eval (context, code.c_str(), code.size(), "", ${type}));\n`;
    insertAfter(line, `                runPendingJobs();\n`);
  }

  insertBefore(`        return returnVal.toChocValue();\n`, `        runPendingJobs();\n`);

  save();
}

//==============================================================================
// The CLAP wrapper

if (!open(join(project, "helpers", "clap", "cmaj_CLAPPlugin.h"))) process.exit(0);

for (const header of ["Bridge.h", "Library.h", "Perf.h"])
  copyFileSync(join(root, "tools", "clap", header), join(project, "helpers", "clap", header));

// the plugin's name, which names its settings folder and its CPU log; before every header of ours
insertBefore(
  `#include "cmajor/helpers/cmaj_PluginHelpers.h"\n`,
  `${marker} the plugin's name, for its settings folder (added by tools/clap-patch.mjs)
#define BRIDGE_PLUGIN_NAME ${JSON.stringify(manifest.name)}

`,
);

insertBefore(
  `#include "cmajor/helpers/cmaj_PluginHelpers.h"\n`,
  `${marker} the patch worker runs in QuickJS, rather than in a hidden web view that takes
// about a second to start (added by tools/clap-patch.mjs)
#ifndef CMAJ_USE_QUICKJS_WORKER
 #define CMAJ_USE_QUICKJS_WORKER 1
#endif

`,
);

insertAfter(
  `#include "choc/gui/choc_DesktopWindow.h"\n`,
  `#include "choc/text/choc_Files.h"\n#include "choc/text/choc_JSON.h"\n#include "choc/memory/choc_Base64.h"\n`,
);
insertAfter(`#include <algorithm>\n`, `#include <cmath>\n#include <cstdlib>\n#include <fstream>\n`);

// The CPU diagnostic (CMAJ_PLUGIN_PERF, tools/clap/Perf.h); after the standard headers
insertAfter(
  `#include <vector>
`,
  `
${marker} an optional CPU diagnostic (added by tools/clap-patch.mjs)
#ifdef _WIN32
 #ifndef NOMINMAX
  #define NOMINMAX
 #endif
 #include <windows.h>
#endif
#include "Perf.h"
`,
);

//==============================================================================
insertAfter(
  `namespace detail
{
`,
  `
${marker} user settings shared by every instance, the host's parameter menu, and the bridge
// the view reaches them through (tools/clap/Bridge.h, added by tools/clap-patch.mjs).
#include "Bridge.h"
`,
);

//==============================================================================
replace(
  `        ViewHolder (cmaj::Patch& patchToUse, std::optional<double> initialScaleFactorToUse)
            : webview (std::make_unique<cmaj::PatchWebView> (patchToUse, findDefaultViewForPatch (patchToUse)))
        {
            if (initialScaleFactorToUse)
                setScaleFactor (*initialScaleFactorToUse);
        }
`,
  `        ViewHolder (cmaj::Patch& patchToUse, std::optional<double> initialScaleFactorToUse, double zoomToUse)
            : webview (std::make_unique<cmaj::PatchWebView> (patchToUse, findDefaultViewForPatch (patchToUse))),
              designWidth (webview->width),
              designHeight (webview->height)
        {
            if (initialScaleFactorToUse)
                setScaleFactor (*initialScaleFactorToUse);

            webview->width  = sizeForZoom (zoomToUse).width;
            webview->height = sizeForZoom (zoomToUse).height;
        }
`,
);

insertBefore(
  `    private:
        void* nativeViewHandle() const`,
  `        ${marker} the view's size relative to the manifest's, which the panel keeps the aspect
        // ratio of
        Size designSize() const     { return { designWidth, designHeight }; }

        double zoom() const
        {
            return bridge::clampZoom (std::min (webview->width / double (designWidth),
                                                  webview->height / double (designHeight)));
        }

        /// The size of the view at a zoom, in host pixels.
        Size hostSizeForZoom (double z) const
        {
            auto s = sizeForZoom (z);
            return { scaled (s.width), scaled (s.height) };
        }

        /// The size nearest to one the host suggests that keeps the aspect ratio.
        Size adjust (Size suggested) const
        {
            auto unscaledExact = [this] (uint32_t x) { return inverseScaleFactor ? *inverseScaleFactor * x : double (x); };

            return hostSizeForZoom (std::min (unscaledExact (suggested.width) / designWidth,
                                              unscaledExact (suggested.height) / designHeight));
        }

        cmaj::PatchWebView& getPatchWebView()     { return *webview; }

        Size sizeForZoom (double z) const
        {
            z = bridge::clampZoom (z);
            return { toIntegerPixel (designWidth * z), toIntegerPixel (designHeight * z) };
        }

`,
);

insertAfter(`        std::unique_ptr<cmaj::PatchWebView> webview;\n`, `        uint32_t designWidth, designHeight;\n`);

insertAfter(
  `    std::optional<ViewHolder> editor;
`,
  `
    ${marker} the size of this instance's editor, kept while it is closed, and the bridge that
    // answers the view's settings and host requests
    std::optional<double> editorZoom;
    std::unique_ptr<bridge::RequestBridge> requestBridge;

    void handleViewRequest (std::string_view);
    void handleSettingsRequest (std::string_view);
    void sendSettingsToView();
    void handleLibraryRequest (std::string_view);

    ${marker} the host's menu for a parameter, which the view asks for and on_main_thread shows
    struct HostMenuRequest
    {
        clap_id param;
        int32_t x, y;
    };

    std::optional<HostMenuRequest> pendingHostMenu;

    bool canShowHostMenu() const;
    void handleHostRequest (std::string_view);
    void sendHostInfoToView();
    void showPendingHostMenu();
`,
);

//==============================================================================
replace(
  `inline bool Plugin::Impl::clapGui_create (const char*, bool)
{
    editor = ViewHolder (patch, cachedViewScaleFactor);
    return true;
}

inline void Plugin::Impl::clapGui_destroy()
{
    editor = {};
}`,
  `inline bool Plugin::Impl::clapGui_create (const char*, bool)
{
    editor = ViewHolder (patch, cachedViewScaleFactor,
                         editorZoom.value_or (bridge::zoomSetting (bridge::loadSettings())));

    requestBridge = std::make_unique<bridge::RequestBridge> (patch, [this] (std::string_view key)
    {
        handleViewRequest (key);
    });

    return true;
}

inline void Plugin::Impl::clapGui_destroy()
{
    requestBridge.reset();
    pendingHostMenu = {};

    if (editor)
        editorZoom = editor->zoom();

    editor = {};
}`,
);

replace(
  `inline bool Plugin::Impl::clapGui_getResizeHints (clap_gui_resize_hints_t*)
{
    return {};
}

inline bool Plugin::Impl::clapGui_adjustSize (uint32_t*, uint32_t*)
{
    return {};
}`,
  `inline bool Plugin::Impl::clapGui_getResizeHints (clap_gui_resize_hints_t* hints)
{
    if (! (editor && editor->resizable()))
        return false;

    const auto design = editor->designSize();
    hints->can_resize_horizontally = true;
    hints->can_resize_vertically = true;
    hints->preserve_aspect_ratio = true;
    hints->aspect_ratio_width = design.width;
    hints->aspect_ratio_height = design.height;
    return true;
}

inline bool Plugin::Impl::clapGui_adjustSize (uint32_t* width, uint32_t* height)
{
    if (! (editor && editor->resizable()))
        return false;

    const auto size = editor->adjust ({ *width, *height });
    *width = size.width;
    *height = size.height;
    return true;
}`,
);

insertBefore(
  `inline void Plugin::Impl::resetIfRequestIsPending()
{`,
  `${marker} a stored-state request from the view (the whole key)
inline void Plugin::Impl::handleViewRequest (std::string_view key)
{
    if (choc::text::startsWith (key, bridge::requestPrefix))
        handleSettingsRequest (key.substr (bridge::requestPrefix.size()));
    else if (choc::text::startsWith (key, bridge::hostRequestPrefix))
        handleHostRequest (key.substr (bridge::hostRequestPrefix.size()));
    else if (choc::text::startsWith (key, bridge::library::requestPrefix))
        handleLibraryRequest (key.substr (bridge::library::requestPrefix.size()));
}

${marker} the bank library's requests (tools/clap/Library.h); some parts aren't answered
inline void Plugin::Impl::handleLibraryRequest (std::string_view request)
{
    if (! editor)
        return;

    auto reply = bridge::bankLibrary().handle (request);

    if (! reply.isVoid())
        editor->getPatchWebView().sendMessage (
            choc::json::create ("type", "state_key_value",
                                "message", choc::json::create ("key", bridge::library::replyKey, "value", reply)));
}

${marker} ?get answers with the settings; ?zoom=<factor> asks the host to resize the window;
// ?save=<json> replaces the settings file. Every request is answered.
inline void Plugin::Impl::handleSettingsRequest (std::string_view request)
{
    if (! editor)
        return;

    if (choc::text::startsWith (request, "zoom="))
    {
        const auto zoom = bridge::clampZoom (std::strtod (std::string (request.substr (5)).c_str(), nullptr));
        const auto size = editor->hostSizeForZoom (zoom);
        const auto hostGui = getExtension<clap_host_gui_t> (host, CLAP_EXT_GUI);

        if (hostGui != nullptr && hostGui->request_resize != nullptr
             && hostGui->request_resize (std::addressof (host), size.width, size.height))
        {
            // some hosts resize the window without calling set_size
            editor->setSize (size);
            editorZoom = zoom;
        }
    }
    else if (choc::text::startsWith (request, "save="))
    {
        try
        {
            auto settings = choc::json::parse (request.substr (5));

            if (settings.isObject())
                bridge::saveSettings (settings);
        }
        catch (...) {}
    }

    sendSettingsToView();
}

inline void Plugin::Impl::sendSettingsToView()
{
    if (! editor)
        return;

    editor->getPatchWebView().sendMessage (
        choc::json::create ("type", "state_key_value",
                            "message", choc::json::create ("key", bridge::replyKey,
                                                           "value", choc::json::create ("settings", bridge::loadSettings(),
                                                                                        "zoom", editor->zoom()))));
}

${marker} whether the host can show its menu for the plugin, which can change once the view
// is in its window
inline bool Plugin::Impl::canShowHostMenu() const
{
    auto menu = bridge::hostContextMenu (host);
    return editor && menu != nullptr && menu->can_popup (std::addressof (host));
}

${marker} ?get answers with what the host offers; ?menu=<json> { id, x, y, scale } shows the
// host's menu for the parameter with that endpoint ID, at a point in the view in CSS pixels,
// scale being the view's device pixel ratio; ?dismiss closes it. The menu is left to
// on_main_thread rather than shown here, inside the web view's message handler.
inline void Plugin::Impl::handleHostRequest (std::string_view request)
{
    if (! editor)
        return;

    if (choc::text::startsWith (request, "menu="))
    {
        try
        {
            auto args = choc::json::parse (request.substr (5));
            auto parameter = patch.findParameter (cmaj::EndpointID::create (args["id"].toString()));

            if (parameter == nullptr || automatableParametersByHandle.count (parameter->endpointHandle) == 0)
                return;

           #if CHOC_OSX
            const double scale = 1.0; // CLAP's coordinates are points on macOS, as are CSS pixels
           #else
            const double scale = args["scale"].getWithDefault<double> (1.0);
           #endif

            const auto toPixel = [scale] (const choc::value::ValueView& v)
            {
                const auto x = v.getWithDefault<double> (0.0) * scale;
                return static_cast<int32_t> (std::isfinite (x) ? std::round (x) : 0.0);
            };

            pendingHostMenu = HostMenuRequest { static_cast<clap_id> (parameter->endpointHandle),
                                                toPixel (args["x"]), toPixel (args["y"]) };
            host.request_callback (std::addressof (host));
        }
        catch (...) {}

        return;
    }

    if (request == "dismiss")
    {
        pendingHostMenu = {};
        bridge::dismissHostMenu();
        return;
    }

    sendHostInfoToView();
}

inline void Plugin::Impl::sendHostInfoToView()
{
    if (! editor)
        return;

    editor->getPatchWebView().sendMessage (
        choc::json::create ("type", "state_key_value",
                            "message", choc::json::create ("key", bridge::hostReplyKey,
                                                           "value", choc::json::create ("menu", canShowHostMenu()))));
}

inline void Plugin::Impl::showPendingHostMenu()
{
    auto request = std::exchange (pendingHostMenu, std::nullopt);

    if (! (request && canShowHostMenu()))
        return;

    const clap_context_menu_target_t target { CLAP_CONTEXT_MENU_TARGET_KIND_PARAM, request->param };
    bridge::hostContextMenu (host)->popup (std::addressof (host), std::addressof (target), 0, request->x, request->y);
}

`,
);

insertAfter(
  `inline void Plugin::Impl::clapPlugin_onMainThread()
{
`,
  `    ${marker} the host's menu that the view asked for
    showPendingHostMenu();
`,
);

//==============================================================================
replace(
  `    return static_cast<uint32_t> (patch.getFramesLatency());`,
  `    ${marker} the latency the DSP declares (processor.latency = ${latencyExpr ?? 0}), which the
    // generated C++ doesn't report
    return static_cast<uint32_t> (std::max (patch.getFramesLatency(), ${latency}.0));`,
);

//==============================================================================
insertAfter(
  `    bool loadPatch (const std::filesystem::path& pathToManifest, FrequencyAndBlockSize frequencyAndBlockSize)
    {
`,
  `        ${marker} a generated plugin's patch never changes, so once it's loaded, activating
        // only needs to rebuild it if the sample rate or block size changed, which
        // setPlaybackParams does (keeping the parameter values). Loading it again from scratch
        // built it three times: preload, setPlaybackParams' rebuild, then loadPatch.
        if (environment.engineType == Environment::EngineType::AOT && patch.isPlayable())
        {
            const auto channels = [] (const cmaj::EndpointDetailsList& endpoints)
            {
                uint32_t count = 0;

                for (const auto& endpoint : endpoints)
                    count += endpoint.getNumAudioChannels();

                return count;
            };

            patch.setPlaybackParams ({
                frequencyAndBlockSize.frequency,
                frequencyAndBlockSize.maxBlockSize,
                channels (patch.getInputEndpoints()),
                channels (patch.getOutputEndpoints()),
            });

            return patch.isPlayable();
        }

`,
);

// The transport goes to the patch only when it changes (a host sends it with every call, and with
// small buffers that is a thousand times a second; each event can cost more than the DSP's own work
// for a block). It is sent again when processing starts, in case the patch was built again. The
// song position goes only to a DSP with a std::timeline::Position input of its own.
const sendsPosition = /std::timeline::Position/.test(dspSources);
insertAfter(`    double frequency = 0;
`, `    ${marker} what was last sent of the transport (see clapPlugin_process's transport case)
    float lastSentTempo = -1.0f;
    int lastSentTimeSig = -1, lastSentTransport = -1;
`);
replace(
  `            patch.sendTransportState (isRecording, isPlaying, isLooping, 0);

            if (event.flags & CLAP_TRANSPORT_HAS_TEMPO)
                patch.sendBPM (static_cast<float> (event.tempo), 0);

            if (event.flags & CLAP_TRANSPORT_HAS_TIME_SIGNATURE)
                patch.sendTimeSig (static_cast<int> (event.tsig_num), static_cast<int> (event.tsig_denom), 0);
`,
  `            ${marker} only what changed
            if (const int transport = (isRecording ? 1 : 0) | (isPlaying ? 2 : 0) | (isLooping ? 4 : 0); transport != lastSentTransport)
            {
                lastSentTransport = transport;
                patch.sendTransportState (isRecording, isPlaying, isLooping, 0);
            }

            if ((event.flags & CLAP_TRANSPORT_HAS_TEMPO) && static_cast<float> (event.tempo) != lastSentTempo)
            {
                lastSentTempo = static_cast<float> (event.tempo);
                patch.sendBPM (lastSentTempo, 0);
            }

            if (event.flags & CLAP_TRANSPORT_HAS_TIME_SIGNATURE)
            {
                if (const int timeSig = (static_cast<int> (event.tsig_num) << 16) | static_cast<int> (event.tsig_denom); timeSig != lastSentTimeSig)
                {
                    lastSentTimeSig = timeSig;
                    patch.sendTimeSig (static_cast<int> (event.tsig_num), static_cast<int> (event.tsig_denom), 0);
                }
            }
${sendsPosition ? "" : "\n            return;   // the DSP has no std::timeline::Position input (see tools/clap-patch.mjs)\n"}`,
);
replace(
  `    blockRestartRequests = false;
    return patch.isPlayable();`,
  `    blockRestartRequests = false;
    lastSentTempo = -1.0f;
    lastSentTimeSig = lastSentTransport = -1;
    return patch.isPlayable();`,
);

// With CMAJ_PLUGIN_PERF set, the process calls are timed and logged (tools/clap/Perf.h)
replace(
  `        return unsafeCastToRef<Plugin> (plugin).impl->clapPlugin_process (process);
`,
  `        auto& impl = *unsafeCastToRef<Plugin> (plugin).impl;

        if (! ::bridge::perf::enabled())
            return impl.clapPlugin_process (process);

        return ::bridge::perf::timerFor (std::addressof (impl)).run (process, [&] { return impl.clapPlugin_process (process); });
`,
);

save();
