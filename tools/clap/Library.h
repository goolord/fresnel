// The bank library: the preset files (banks, or lone presets) found in folders the user adds to
// the preset browser, and the files opened in it, copied into a folder of their own
// (<settings folder>/banks) with an index (index.json). The browser lists them from there without
// walking the folders again, and keeps them when the plugin window closes, or when a folder is out
// of reach (a drive that isn't plugged in).
//
// It knows nothing of the files' formats: the view says which extensions to look for (the formats
// the plugin registers, ui/presets/PresetFormat.res) and reads the files itself.
//
// The view asks through stored-state requests whose key starts with "bridge:library?" (see
// tools/clap-patch.mjs and ui/presets/BankLibrary.res), and the plugin answers with a
// "bridge:library" value:
//   ?list                       the banks
//   ?scan=<json {folders: [...], extensions: [".preset", ...]}>
//                               walks the folders for files with those extensions, copies those
//                               that are new or changed and drops those that are gone (a folder
//                               that isn't there keeps its banks), then answers with the banks
//   ?read=<json {id, part}>     part of a bank's file: { read: { id, part, parts, data } }, the
//                               data in base64, or { read: { id, error } }
//   ?put=<json {id, name, ext, part, parts, data}>   a file opened in the browser, in parts of
//                               base64; the last part adds it, and is answered with the banks
//   ?remove=<id>                forgets an opened file, and answers with the banks
// The banks are { banks: [ { id, name, origin ("folder" | "opened"), path, folder, size,
// modified, file } ], scanned: [the folders the last scan walked], extensions: [what it looked
// for] }; a bank's file is its id and its extension, which tells the view its format. The view
// asks for ?list when it opens and scans only when its folders or extensions aren't the scanned
// ones (a new folder, a plugin that reads a new format, or an index from before they were kept)
// or when the user asks.
//
// No includes of its own: Bridge.h includes it where the headers it needs already are
// (<filesystem>, <fstream>, <vector>, choc's files, JSON and base64), and so can a test
// (tools/test/library.cpp).

#pragma once

namespace bridge::library
{
    inline const std::string requestPrefix = "bridge:library?";
    inline const std::string replyKey = "bridge:library";

    constexpr uintmax_t maxFileSize = 32 * 1024 * 1024;
    constexpr size_t chunkSize = 512 * 1024;
    constexpr int maxDepth = 8;
    constexpr size_t maxVisited = 50000;

    inline std::string utf8 (const std::filesystem::path& p)
    {
        auto s = p.u8string();
        return std::string (s.begin(), s.end());
    }

    inline std::filesystem::path fromUtf8 (std::string_view s)
    {
       #if __cplusplus >= 202002L
        return std::filesystem::path (std::u8string (s.begin(), s.end()));
       #else
        return std::filesystem::u8path (s.begin(), s.end());
       #endif
    }

    /// An id from a path or a file's contents (FNV-1a, in hex), after a letter for its origin.
    inline std::string hashId (char prefix, std::string_view s)
    {
        uint64_t h = 1469598103934665603ull;

        for (auto c : s)
        {
            h ^= static_cast<uint8_t> (c);
            h *= 1099511628211ull;
        }

        std::string id (1, prefix);

        for (int shift = 60; shift >= 0; shift -= 4)
            id += "0123456789abcdef"[(h >> shift) & 15];

        return id;
    }

    /// Ids name the cached files, so they're kept to letters and digits.
    inline bool isSafeId (std::string_view id)
    {
        if (id.empty() || id.size() > 40)
            return false;

        for (auto c : id)
            if (! ((c >= 'a' && c <= 'z') || (c >= '0' && c <= '9')))
                return false;

        return true;
    }

    inline std::string toLower (std::string s)
    {
        for (auto& c : s)
            if (c >= 'A' && c <= 'Z')
                c = static_cast<char> (c - 'A' + 'a');

        return s;
    }

    inline std::string lowerExtension (const std::filesystem::path& p)
    {
        return toLower (utf8 (p.extension()));
    }

    /// An extension names the cached files too, so it's a dot and a few letters, digits, '-' or
    /// '_' (one dot: a path's extension is what follows its last one).
    inline bool isSafeExtension (std::string_view ext)
    {
        if (ext.size() < 2 || ext.size() > 16 || ext[0] != '.')
            return false;

        for (auto c : ext.substr (1))
            if (! ((c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c == '-' || c == '_'))
                return false;

        return true;
    }

    /// The extensions a scan asks for, in lower case, leaving out any that aren't safe.
    inline std::vector<std::string> extensionsOf (const choc::value::ValueView& list)
    {
        std::vector<std::string> extensions;

        for (uint32_t i = 0; i < (list.isArray() ? list.size() : 0); ++i)
        {
            if (! list[i].isString())
                continue;

            auto ext = toLower (std::string (list[i].getString()));

            if (isSafeExtension (ext) && std::find (extensions.begin(), extensions.end(), ext) == extensions.end())
                extensions.push_back (ext);
        }

        return extensions;
    }

    inline double modifiedTime (const std::filesystem::path& p)
    {
        std::error_code ec;
        auto t = std::filesystem::last_write_time (p, ec);
        return ec ? 0.0 : static_cast<double> (t.time_since_epoch().count());
    }

    //==============================================================================
    /// The library in a folder (cache): its index, and the requests above.
    struct Library
    {
        std::filesystem::path cache;

        std::filesystem::path indexFile() const     { return cache / "index.json"; }

        choc::value::Value loadIndex() const
        {
            try
            {
                if (std::filesystem::exists (indexFile()))
                {
                    auto index = choc::json::parse (choc::file::loadFileAsString (indexFile()));

                    if (index.isObject() && index["banks"].isArray())
                        return index;
                }
            }
            catch (...) {}

            return withBanks (choc::value::createEmptyArray());
        }

        /// An index of these banks, with what the last scan walked (the folders and extensions)
        /// taken from `last` (an index, or void): the view scans on its own only when the
        /// folders or extensions it wants are others.
        static choc::value::Value withBanks (const choc::value::ValueView& banks, const choc::value::ValueView& last = {})
        {
            auto index = choc::value::createObject ({});
            index.addMember ("banks", banks);

            for (auto key : { "scanned", "extensions" })
                if (last.isObject() && last.hasObjectMember (key) && last[key].isArray())
                    index.addMember (key, last[key]);

            return index;
        }

        void saveIndex (const choc::value::ValueView& index) const
        {
            std::error_code ec;
            std::filesystem::create_directories (cache, ec);
            choc::file::replaceFileWithContent (indexFile(), choc::json::toString (index, true));
        }

        static choc::value::Value entry (std::string_view id, std::string_view name, std::string_view file,
                                         std::string_view origin, std::string_view path, std::string_view folder,
                                         double size, double modified)
        {
            return choc::json::create ("id", std::string (id), "name", std::string (name), "file", std::string (file),
                                       "origin", std::string (origin), "path", std::string (path),
                                       "folder", std::string (folder), "size", size, "modified", modified);
        }

        /// The index's entry with this id, or void.
        static choc::value::Value find (const choc::value::ValueView& banks, std::string_view id)
        {
            for (uint32_t i = 0; i < banks.size(); ++i)
                if (banks[i]["id"].toString() == id)
                    return choc::value::Value (banks[i]);

            return {};
        }

        static bool listed (const choc::value::ValueView& banks, std::string_view id)
        {
            return find (banks, id).isObject();
        }

        /// Deletes the cached files of the old entries that aren't in the new list.
        void removeDropped (const choc::value::ValueView& oldBanks, const choc::value::ValueView& banks) const
        {
            for (uint32_t i = 0; i < oldBanks.size(); ++i)
            {
                auto old = oldBanks[i];

                if (! listed (banks, old["id"].toString()))
                {
                    std::error_code ec;
                    std::filesystem::remove (cache / fromUtf8 (old["file"].toString()), ec);
                }
            }
        }

        /// Walks args.folders for files with one of args.extensions.
        choc::value::Value scan (const choc::value::ValueView& args) const
        {
            namespace fs = std::filesystem;
            auto folders = args.isObject() && args.hasObjectMember ("folders") ? args["folders"] : choc::value::ValueView();
            auto extensions = extensionsOf (args.isObject() && args.hasObjectMember ("extensions") ? args["extensions"]
                                                                                                   : choc::value::ValueView());
            auto index = loadIndex();
            auto oldBanks = index["banks"];
            auto banks = choc::value::createEmptyArray();
            // folders that aren't there, or whose walk stopped early: they keep the banks not found
            std::vector<std::string> unreachable;
            std::error_code ec;
            fs::create_directories (cache, ec);

            for (uint32_t f = 0; f < (folders.isArray() ? folders.size() : 0); ++f)
            {
                if (! folders[f].isString())
                    continue;

                auto folderText = folders[f].toString();
                auto root = fromUtf8 (folderText);

                if (! fs::is_directory (root, ec))
                {
                    unreachable.push_back (folderText);
                    continue;
                }

                size_t visited = 0;
                bool cutShort = false;

                for (auto it = fs::recursive_directory_iterator (root, fs::directory_options::skip_permission_denied, ec);
                     ! ec && it != fs::recursive_directory_iterator(); it.increment (ec))
                {
                    if (++visited > maxVisited)
                    {
                        cutShort = true;
                        break;
                    }

                    if (it.depth() >= maxDepth)
                        it.disable_recursion_pending();

                    std::error_code fileError;

                    if (! it->is_regular_file (fileError))
                        continue;

                    const auto& path = it->path();
                    auto ext = lowerExtension (path);

                    if (std::find (extensions.begin(), extensions.end(), ext) == extensions.end())
                        continue;

                    auto size = it->file_size (fileError);

                    if (fileError || size == 0 || size > maxFileSize)
                        continue;

                    auto pathText = utf8 (path);
                    auto id = hashId ('f', pathText);

                    if (listed (banks, id))
                        continue;

                    auto modified = modifiedTime (path);
                    auto file = id + ext;
                    auto previous = find (oldBanks, id);
                    auto unchanged = previous.isObject()
                                      && previous["size"].getWithDefault<double> (-1.0) == static_cast<double> (size)
                                      && previous["modified"].getWithDefault<double> (-1.0) == modified
                                      && fs::exists (cache / file, fileError);

                    // (whether the file really is one is the view's to find out: it reads them)
                    if (! unchanged)
                    {
                        fs::copy_file (path, cache / file, fs::copy_options::overwrite_existing, fileError);

                        if (fileError)
                            continue;
                    }

                    banks.addArrayElement (entry (id, utf8 (path.stem()), file, "folder", pathText, folderText,
                                                  static_cast<double> (size), modified));
                }

                // (an entry the walk can't step past ends it, as the visit limit does)
                if (ec || cutShort)
                    unreachable.push_back (folderText);

                ec.clear();
            }

            // opened files stay, and so do the banks of a folder that's still listed but out of reach
            // (or that was only partly walked)
            for (uint32_t i = 0; i < oldBanks.size(); ++i)
            {
                auto old = oldBanks[i];
                auto origin = old["origin"].toString();
                auto folder = old["folder"].toString();
                auto keep = origin == "opened"
                             || std::find (unreachable.begin(), unreachable.end(), folder) != unreachable.end();

                if (keep && ! listed (banks, old["id"].toString()))
                    banks.addArrayElement (old);
            }

            removeDropped (oldBanks, banks);
            auto extensionList = choc::value::createEmptyArray();

            for (auto& e : extensions)
                extensionList.addArrayElement (e);

            auto updated = withBanks (banks, choc::json::create ("scanned", folders.isArray() ? choc::value::Value (folders)
                                                                                               : choc::value::createEmptyArray(),
                                                                 "extensions", extensionList));
            saveIndex (updated);
            return updated;
        }

        choc::value::Value read (const choc::value::ValueView& args) const
        {
            auto id = args["id"].toString();
            auto part = args["part"].getWithDefault<int64_t> (0);
            auto bank = find (loadIndex()["banks"], id);
            auto fail = [&] (std::string_view why)
            {
                return choc::json::create ("read", choc::json::create ("id", id, "error", std::string (why)));
            };

            if (! bank.isObject())
                return fail ("not in the library");

            std::string content;

            try
            {
                content = choc::file::loadFileAsString (cache / fromUtf8 (bank["file"].toString()));
            }
            catch (...)
            {
                return fail ("its copy can't be read");
            }

            auto parts = static_cast<int64_t> (std::max<size_t> (1, (content.size() + chunkSize - 1) / chunkSize));

            if (part < 0 || part >= parts)
                return fail ("no such part");

            auto from = static_cast<size_t> (part) * chunkSize;
            auto length = std::min (chunkSize, content.size() - from);

            return choc::json::create ("read", choc::json::create ("id", id, "part", part, "parts", parts,
                                                                   "data", choc::base64::encodeToString (content.data() + from, length)));
        }

        /// A part of an opened file; void until its last part.
        choc::value::Value put (const choc::value::ValueView& args) const
        {
            namespace fs = std::filesystem;
            auto id = args["id"].toString();
            auto ext = toLower (args["ext"].toString());
            auto part = args["part"].getWithDefault<int64_t> (0);
            auto parts = args["parts"].getWithDefault<int64_t> (1);

            if (! isSafeId (id) || ! isSafeExtension (ext))
                return {};

            std::vector<uint8_t> bytes;

            if (! choc::base64::decodeToContainer (bytes, args["data"].toString()))
                return {};

            std::error_code ec;
            fs::create_directories (cache, ec);
            auto partial = cache / (id + ".part");

            {
                std::ofstream out (partial, std::ios::binary | (part == 0 ? std::ios::trunc : std::ios::app));
                out.write (reinterpret_cast<const char*> (bytes.data()), static_cast<std::streamsize> (bytes.size()));
            }

            if (part + 1 < parts)
                return {};

            auto file = id + ext;
            fs::remove (cache / file, ec);
            fs::rename (partial, cache / file, ec);

            if (ec)
                return loadIndex();

            auto index = loadIndex();
            auto oldBanks = index["banks"];
            auto banks = choc::value::createEmptyArray();

            for (uint32_t i = 0; i < oldBanks.size(); ++i)
                if (oldBanks[i]["id"].toString() != id)
                    banks.addArrayElement (oldBanks[i]);

            // (the same file under another extension: its old copy goes)
            auto previous = find (oldBanks, id);

            if (previous.isObject() && previous["file"].toString() != file)
                fs::remove (cache / fromUtf8 (previous["file"].toString()), ec);

            banks.addArrayElement (entry (id, args["name"].toString(), file, "opened", {}, {},
                                          static_cast<double> (fs::file_size (cache / file, ec)), modifiedTime (cache / file)));
            auto updated = withBanks (banks, index);
            saveIndex (updated);
            return updated;
        }

        choc::value::Value remove (std::string_view id) const
        {
            auto index = loadIndex();
            auto oldBanks = index["banks"];
            auto banks = choc::value::createEmptyArray();

            for (uint32_t i = 0; i < oldBanks.size(); ++i)
                if (! (oldBanks[i]["id"].toString() == id && oldBanks[i]["origin"].toString() == "opened"))
                    banks.addArrayElement (oldBanks[i]);

            removeDropped (oldBanks, banks);
            auto updated = withBanks (banks, index);
            saveIndex (updated);
            return updated;
        }

        /// A request (the key after the prefix); its answer, or void for none.
        choc::value::Value handle (std::string_view request) const
        {
            try
            {
                auto argument = [&] (size_t length) { return choc::json::parse (request.substr (length)); };

                if (choc::text::startsWith (request, "scan="))      return scan (argument (5));
                if (choc::text::startsWith (request, "read="))      return read (argument (5));
                if (choc::text::startsWith (request, "put="))       return put (argument (4));
                if (choc::text::startsWith (request, "remove="))    return remove (request.substr (7));

                return loadIndex();
            }
            catch (...)
            {
                return choc::json::create ("error", std::string ("the library request failed"));
            }
        }
    };
}
