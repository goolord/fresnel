// Reads files the patch bundles ("resources" in the manifest: presets/* and the factory
// bank), for the worker and the view.

open PatchConnection

type response
@get_index external member: (resource, string) => unknown = ""
@get external readResourceMember: t => unknown = "readResource"
@val external fetch: string => promise<resource> = "fetch"
external asResponse: resource => response = "%identity"
@get external ok: response => option<bool> = "ok"
@send external arrayBuffer: response => promise<ArrayBuffer.t> = "arrayBuffer"
@send external text: response => promise<string> = "text"
@val external isView: Type.Classify.object => bool = "ArrayBuffer.isView"
@val external codePoints: string => array<string> = "Array.from"
external asView: Type.Classify.object => Uint8Array.t = "%identity"
external asBuffer: Type.Classify.object => ArrayBuffer.t = "%identity"
external asBytes: Type.Classify.object => array<int> = "%identity"

let utf8 = text =>
  text
  ->codePoints
  ->Array.flatMap(ch => {
    let c = String.codePointAt(ch, 0)->Option.getOr(0)
    if c < 0x80 {
      [c]
    } else if c < 0x800 {
      [0xc0 ||| c >> 6, 0x80 ||| c &&& 63]
    } else if c < 0x10000 {
      [0xe0 ||| c >> 12, 0x80 ||| c >> 6 &&& 63, 0x80 ||| c &&& 63]
    } else {
      [0xf0 ||| c >> 18, 0x80 ||| c >> 12 &&& 63, 0x80 ||| c >> 6 &&& 63, 0x80 ||| c &&& 63]
    }
  })
  ->Uint8Array.fromArray

// readResource returns different things depending on the runtime: the native worker gives
// an array of (signed) byte values, or a string when the file happens to be valid UTF-8; the
// WebAudio runtime gives a fetch Response.
let toBytes = async (data: resource) =>
  if Type.typeof(data->member("arrayBuffer")) == #function {
    let response = asResponse(data)
    response->ok == Some(false) ? None : Some(Uint8Array.fromBuffer(await response->arrayBuffer))
  } else {
    switch Type.Classify.classify(data) {
    | String(text) => Some(utf8(text))
    | Object(o) if Array.isArray(o) => Some(Uint8Array.fromArrayLikeOrIterable(asBytes(o))) // wraps negative values to 0..255
    | Object(o) if isView(o) =>
      let view = asView(o)
      Some(
        Uint8Array.fromBuffer(
          view->TypedArray.buffer,
          ~byteOffset=view->TypedArray.byteOffset,
          ~length=view->TypedArray.byteLength,
        ),
      )
    | Object(o) => Some(Uint8Array.fromBuffer(asBuffer(o))) // empty unless it's an ArrayBuffer
    | _ => None
    }
  }

// A text file: the native worker gives it as a string already (if it's valid UTF-8), which is
// much quicker there than going through the bytes.
let toText = async (data: resource) =>
  switch Type.Classify.classify(data) {
  | String(text) => Some(text)
  | Object(_) if Type.typeof(data->member("text")) == #function =>
    let response = asResponse(data)
    response->ok == Some(false) ? None : Some(await response->text)
  | _ => None
  }

// The native view's connection has no readResource, but its web view serves the patch's
// files, so it fetches them.
let readResource = (pc, path) =>
  Type.typeof(pc->readResourceMember) == #function
    ? pc->PatchConnection.readResource(path)
    : fetch(pc->getResourceAddress(path))

// Reads a resource with `convert`, trying the path as it is, then from the root.
let read = async (pc, path, convert, ~isEmpty) => {
  let rec attempt = async paths =>
    switch paths {
    | list{} => None
    | list{p, ...rest} =>
      let content = try await convert(await readResource(pc, p)) catch {
      | _ => None
      }
      switch content {
      | Some(c) if !isEmpty(c) => content
      | _ => await attempt(rest)
      }
    }
  await attempt(list{path, "/" ++ path})
}

let readBytes = (pc, path) => read(pc, path, toBytes, ~isEmpty=b => TypedArray.length(b) == 0)
let readText = (pc, path) => read(pc, path, toText, ~isEmpty=s => s == "")
