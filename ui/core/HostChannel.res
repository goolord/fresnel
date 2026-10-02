// A request/reply channel to the CLAP plugin through the patch's stored state (see
// tools/clap-patch.mjs): a request asks for the stored-state value "bridge:<name>?<what>", and
// the plugin answers with a "bridge:<name>" value, an object. Nothing is stored: the plugin answers
// the request itself. Elsewhere (cmaj play, the UI preview) nothing answers, so everything that
// uses a channel must work without a reply.

type t = {
  pc: PatchConnection.t,
  replyKey: string,
  mutable listener: option<PatchConnection.storedStateEvent => unit>,
}

let make = (pc, name) => {pc, replyKey: "bridge:" ++ name, listener: None}

let request = (t, what) => t.pc->PatchConnection.requestStoredStateValue(t.replyKey ++ "?" ++ what)

// Calls onReply with every answer, until dispose.
let listen = (t, onReply) => {
  let listener = ({key, value}: PatchConnection.storedStateEvent) =>
    switch value {
    | Object(reply) if key == t.replyKey => onReply(reply)
    | _ => ()
    }
  t.listener = Some(listener)
  t.pc->PatchConnection.addStoredStateValueListener(listener)
}

let dispose = t =>
  t.listener->Option.forEach(listener => t.pc->PatchConnection.removeStoredStateValueListener(listener))
