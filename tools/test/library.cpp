// Checks the plugin's bank library (tools/clap/Library.h) on real files: scanning a folder copies
// the files with the extensions asked for and skips the rest, a rescan keeps unchanged banks and
// follows changes, parts read back as the file, opened files are added and removed, and a folder
// out of reach keeps its banks.
//
// It needs choc, which the generated CLAP project brings (build/clap-project/include/choc, there
// after a first `just` build). From the repo root:
//
//   clang++ -std=c++17 -Ibuild/clap-project/include/choc tools/test/library.cpp -o build/test/library.exe
//   build/test/library.exe

#include <algorithm>
#include <chrono>
#include <cstdint>
#include <cstdio>
#include <filesystem>
#include <fstream>
#include <string>
#include <vector>
#include "choc/text/choc_Files.h"
#include "choc/text/choc_JSON.h"
#include "choc/text/choc_StringUtilities.h"
#include "choc/memory/choc_Base64.h"
#include "../clap/Library.h"

namespace fs = std::filesystem;
static int failures = 0;

static void check (bool ok, const char* what)
{
    std::printf ("%s %s\n", ok ? "ok  " : "FAIL", what);
    if (! ok) ++failures;
}

static void write (const fs::path& p, const std::string& content)
{
    fs::create_directories (p.parent_path());
    std::ofstream (p, std::ios::binary) << content;
}

static int count (const choc::value::ValueView& index, std::string_view origin)
{
    int n = 0;
    for (uint32_t i = 0; i < index["banks"].size(); ++i)
        if (index["banks"][i]["origin"].toString() == origin) ++n;
    return n;
}

int main()
{
    std::setvbuf (stdout, nullptr, _IONBF, 0);
    auto root = fs::temp_directory_path() / "bridge-library-test";
    fs::remove_all (root);
    auto folder = root / "my presets";
    bridge::library::Library library { root / "cache" };

    std::string bank = "{\"name\":\"b\",\"presets\":[]}";
    std::string big (1300 * 1024, 'x');
    big = "{" + big;
    write (folder / "one.preset", bank);
    write (folder / "sub" / "deeper" / "two.BANK", std::string (100, '\0'));
    write (folder / "big.preset", big);
    write (folder / "notes.txt", "not a preset");
    write (folder / "other.json", "{}");

    auto folders = choc::json::parse ("[" + choc::json::getEscapedQuotedString (bridge::library::utf8 (folder)) + "]");
    auto scanRequest = [&] (const choc::value::ValueView& which, std::string_view extensions)
    {
        return "scan={\"folders\":" + choc::json::toString (which) + ",\"extensions\":" + std::string (extensions) + "}";
    };
    auto scanned = library.handle (scanRequest (folders, "[\".preset\",\".bank\",\"../x\"]"));
    check (count (scanned, "folder") == 3, "a scan finds the files with the extensions asked for (in any case) and skips the rest");
    check (fs::exists (root / "cache" / "index.json"), "the index is written");
    check (choc::json::toString (library.handle ("list")["scanned"]) == choc::json::toString (folders),
           "the index remembers the folders it scanned, for a list to answer");
    check (choc::json::toString (library.handle ("list")["extensions"]) == "[\".preset\", \".bank\"]",
           "and the extensions (less an unsafe one)");

    auto id = [&] (const choc::value::ValueView& index, std::string_view name)
    {
        for (uint32_t i = 0; i < index["banks"].size(); ++i)
            if (index["banks"][i]["name"].toString() == name) return index["banks"][i]["id"].toString();
        return std::string();
    };
    check (fs::exists (root / "cache" / (id (scanned, "two") + ".bank")), "a copy is named by its id and its extension");

    // reading the big one back in parts
    {
        std::string back;
        int64_t parts = 1;
        for (int64_t part = 0; part < parts; ++part)
        {
            auto reply = library.handle ("read=" + choc::json::toString (choc::json::create ("id", id (scanned, "big"), "part", part)));
            auto r = reply["read"];
            parts = r["parts"].getWithDefault<int64_t> (0);
            std::vector<uint8_t> bytes;
            choc::base64::decodeToContainer (bytes, r["data"].toString());
            back.append (bytes.begin(), bytes.end());
        }
        check (parts == 3 && back == big, "a bank reads back in parts");
    }

    // a rescan follows a changed file and a removed one
    write (folder / "one.preset", bank + " ");
    fs::last_write_time (folder / "one.preset", fs::last_write_time (folder / "one.preset") + std::chrono::seconds (5));
    fs::remove (folder / "big.preset");
    auto rescanned = library.handle (scanRequest (folders, "[\".preset\",\".bank\"]"));
    check (count (rescanned, "folder") == 2, "a rescan drops a bank that's gone");
    check (! fs::exists (root / "cache" / (id (scanned, "big") + ".preset")), "and its copy");
    check (choc::file::loadFileAsString (root / "cache" / (id (rescanned, "one") + ".preset")) == bank + " ",
           "a rescan copies a changed bank again");
    check (count (library.handle (scanRequest (folders, "[\".bank\"]")), "folder") == 1,
           "a scan for fewer extensions drops the others");
    library.handle (scanRequest (folders, "[\".preset\",\".bank\"]"));

    // an opened file, in two parts
    std::string opened = "{\"name\":\"Opened\"}";
    auto put = [&] (int part, std::string_view data, std::string_view ext = ".preset")
    {
        return library.handle ("put=" + choc::json::toString (choc::json::create (
            "id", std::string ("o0123abc"), "name", std::string ("Opened"), "ext", std::string (ext),
            "part", part, "parts", 2, "data", choc::base64::encodeToString (data.data(), data.size()))));
    };
    check (put (0, std::string_view (opened).substr (0, 5)).isVoid(), "a part before the last isn't answered");
    auto withOpened = put (1, std::string_view (opened).substr (5));
    check (count (withOpened, "opened") == 1
             && choc::file::loadFileAsString (root / "cache" / "o0123abc.preset") == opened, "an opened file is added");
    check (choc::json::toString (withOpened["scanned"]) == choc::json::toString (folders)
             && withOpened["extensions"].size() == 2, "and the scanned folders and extensions are kept");

    // a folder out of reach keeps its banks, and so does the opened file
    fs::rename (folder, root / "moved");
    auto unreachable = library.handle (scanRequest (folders, "[\".preset\",\".bank\"]"));
    check (count (unreachable, "folder") == 2 && count (unreachable, "opened") == 1, "a folder out of reach keeps its banks");

    // removing the folder from the list drops its banks
    auto none = library.handle (scanRequest (choc::json::parse ("[]"), "[\".preset\",\".bank\"]"));
    check (count (none, "folder") == 0 && count (none, "opened") == 1, "a folder taken off the list loses its banks");

    auto removed = library.handle ("remove=o0123abc");
    check (count (removed, "opened") == 0 && ! fs::exists (root / "cache" / "o0123abc.preset"), "an opened file is removed");
    check (removed["scanned"].isArray() && removed["scanned"].size() == 0, "the scanned folders survive that too (none, after the empty scan)");
    check (library.handle ("list")["banks"].size() == 0, "the list is empty");
    check (library.handle ("put={\"id\":\"../x\",\"ext\":\".preset\",\"data\":\"\"}").isVoid(), "an unsafe id is refused");
    check (put (1, "x", "/../x").isVoid() && put (1, "x", ".a.b").isVoid(), "and so is an unsafe extension");

    fs::remove_all (root);
    std::printf (failures == 0 ? "bank library ok\n" : "%d failures\n", failures);
    return failures == 0 ? 0 : 1;
}
