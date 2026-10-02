// The template's additions to Cmajor's CLAP wrapper: user settings shared by every instance, the
// host's parameter menu, the bank library (Library.h), and the bridge the view reaches them
// through. tools/clap-patch.mjs copies this and Library.h next to helpers/clap/cmaj_CLAPPlugin.h
// and includes it inside that file's cmaj::plugin::clap::detail namespace, after the headers it
// needs (choc's files, JSON and base64, <cmath>, <cstdlib>, <fstream>), so it has no includes of
// its own but that one. It also defines BRIDGE_PLUGIN_NAME, the plugin's name from the manifest,
// which names the settings folder.

#pragma once

#include "Library.h"

namespace bridge
{
    inline const std::string requestPrefix = "bridge:settings?";
    inline const std::string replyKey = "bridge:settings";
    inline const std::string hostRequestPrefix = "bridge:host?";
    inline const std::string hostReplyKey = "bridge:host";

    constexpr double minZoom = 0.5, maxZoom = 3.0;

    inline double clampZoom (double z)
    {
        return std::isfinite (z) ? std::clamp (z, minZoom, maxZoom) : 1.0;
    }

    inline std::filesystem::path settingsFile()
    {
       #if CHOC_WINDOWS
        wchar_t* appData = nullptr;
        size_t length = 0;

        if (_wdupenv_s (&appData, &length, L"APPDATA") == 0 && appData != nullptr)
        {
            std::filesystem::path folder (appData);
            free (appData);
            return folder / BRIDGE_PLUGIN_NAME / "settings.json";
        }
       #elif CHOC_OSX
        if (auto home = std::getenv ("HOME"))
            return std::filesystem::path (home) / "Library" / "Application Support" / BRIDGE_PLUGIN_NAME / "settings.json";
       #else
        if (auto config = std::getenv ("XDG_CONFIG_HOME"); config != nullptr && *config != 0)
            return std::filesystem::path (config) / BRIDGE_PLUGIN_NAME / "settings.json";

        if (auto home = std::getenv ("HOME"))
            return std::filesystem::path (home) / ".config" / BRIDGE_PLUGIN_NAME / "settings.json";
       #endif

        return {};
    }

    inline choc::value::Value loadSettings()
    {
        try
        {
            auto file = settingsFile();

            if (! file.empty() && std::filesystem::exists (file))
            {
                auto settings = choc::json::parse (choc::file::loadFileAsString (file));

                if (settings.isObject())
                    return settings;
            }
        }
        catch (...) {}

        return choc::value::createObject ({});
    }

    inline void saveSettings (const choc::value::ValueView& settings)
    {
        try
        {
            auto file = settingsFile();

            if (! file.empty())
            {
                std::filesystem::create_directories (file.parent_path());
                choc::file::replaceFileWithContent (file, choc::json::toString (settings, true));
            }
        }
        catch (...) {}
    }

    /// The bank library, beside the settings file.
    inline library::Library bankLibrary()
    {
        auto file = settingsFile();
        return { file.empty() ? std::filesystem::path() : file.parent_path() / "banks" };
    }

    inline double zoomSetting (const choc::value::ValueView& settings)
    {
        return clampZoom (settings.isObject() ? settings["zoom"].getWithDefault<double> (1.0) : 1.0);
    }

    /// The host's context menu extension, if it can show its menu for the plugin.
    inline const clap_host_context_menu_t* hostContextMenu (const clap_host_t& host)
    {
        for (auto id : { CLAP_EXT_CONTEXT_MENU, CLAP_EXT_CONTEXT_MENU_COMPAT })
        {
            auto menu = static_cast<const clap_host_context_menu_t*> (host.get_extension (std::addressof (host), id));

            if (menu != nullptr && menu->can_popup != nullptr && menu->popup != nullptr)
                return menu;
        }

        return nullptr;
    }

    /// Closes the menu the host is showing for the plugin. On Windows a press or a key in the
    /// view never reaches it, since the web view's window belongs to another process: a host's
    /// own menu window (FL Studio's) holds the mouse capture of the host's thread, which only
    /// sees presses on that thread's windows, and a Win32 menu sees none either.
    inline void dismissHostMenu()
    {
       #if CHOC_WINDOWS
        EndMenu();

        if (auto capture = GetCapture())
        {
            DWORD process = 0;
            GetWindowThreadProcessId (capture, &process);

            // losing the capture closes it (DefWindowProc releases it)
            if (process == GetCurrentProcessId())
                SendMessageW (capture, WM_CANCELMODE, 0, 0);
        }
       #endif
    }

    /// Listens to what the patch sends its views, and passes on the settings, host and library
    /// requests (the whole key).
    struct RequestBridge  : public cmaj::PatchView
    {
        RequestBridge (cmaj::Patch& p, std::function<void(std::string_view)> handleToUse)
            : cmaj::PatchView (p), handle (std::move (handleToUse))
        {}

        void sendMessage (const choc::value::ValueView& msg) override
        {
            if (! msg.isObject() || msg["type"].toString() != "state_key_value")
                return;

            auto message = msg["message"];

            if (! message.isObject())
                return;

            auto key = message["key"].toString();

            if (choc::text::startsWith (key, requestPrefix) || choc::text::startsWith (key, hostRequestPrefix)
                 || choc::text::startsWith (key, library::requestPrefix))
                handle (key);
        }

        std::function<void(std::string_view)> handle;
    };
}
