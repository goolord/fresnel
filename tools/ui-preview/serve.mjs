// Serves the project folder for the UI preview (tools/ui-preview/index.html): `npm run preview`,
// then open http://localhost:8123/tools/ui-preview/. GET /presets/?list answers with the names of
// the files in presets/, for the preview's stand-in bank library.
//
//   node tools/ui-preview/serve.mjs [port]   (or the PORT environment variable)

import { createServer } from "node:http";
import { readFile, readdir } from "node:fs/promises";
import { join, extname, normalize, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const root = join(dirname(fileURLToPath(import.meta.url)), "..", "..");
const port = Number(process.argv[2] ?? process.env.PORT ?? 8123);
const types = {
  ".html": "text/html", ".js": "text/javascript", ".mjs": "text/javascript", ".json": "application/json",
  ".css": "text/css", ".svg": "image/svg+xml", ".png": "image/png", ".wasm": "application/wasm",
  ".cmajorpatch": "application/json",
};

createServer(async (req, res) => {
  const url = new URL(req.url, "http://localhost");
  try {
    if (url.pathname === "/presets/" && url.searchParams.has("list")) {
      res.writeHead(200, { "content-type": "application/json" });
      return res.end(JSON.stringify(await readdir(join(root, "presets")).catch(() => [])));
    }
    const path = normalize(join(root, decodeURIComponent(url.pathname)));
    if (!path.startsWith(root)) throw new Error("outside the project");
    const file = path.endsWith("/") || path.endsWith("\\") ? join(path, "index.html") : path;
    const body = await readFile(file);
    res.writeHead(200, { "content-type": types[extname(file)] ?? "application/octet-stream", "cache-control": "no-store" });
    res.end(body);
  } catch {
    res.writeHead(404);
    res.end("not found");
  }
}).listen(port, () => console.log(`UI preview: http://localhost:${port}/tools/ui-preview/`));
