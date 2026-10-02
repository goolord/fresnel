// A level meter: a bar per channel, filled from the bottom on a dB scale (~floor .. 0 dB at the
// top, so -60 .. 0 by default), with a peak line that holds for a second and then falls. A bar
// turns hot (`.bar.hot`) while its held peak is at or over 0 dB, until the hold runs out. Click
// it to drop the held peaks. Over it, the status line reads out the levels and peaks.
//
// It is fed by an output endpoint of the patch (~endpoint) sending linear peak levels, one per
// channel, as JSON: [l, r] from a float<2> (a single number works for a mono meter). Send the
// peak over a few blocks, about 30 times a second; the bars fall by themselves between messages,
// and to the floor when the messages stop (after 300 ms), so the patch may go quiet with its
// output. In the patch:
//
//   output event float<2> meterOut;
//   float<2> held;  int heldFrames;
//
//   // in the processor's loop, for each frame x:
//   held = max (held, abs (x));
//   if (++heldFrames >= int (processor.frequency / 30))
//   {
//       meterOut <- float<2> (held[0], held[1]);
//       held = float<2>();  heldFrames = 0;
//   }
//
// Messages are taken as they come and drawn at most once a frame; while anything moves (a bar
// falling, a peak line coming down) it draws every frame, and stops when everything rests.

open! Web

type t = {
  root: element,
  // drops the held peaks
  reset: unit => unit,
  // feeds levels as the endpoint would (linear peaks)
  feed: array<float> => unit,
}

// how fast the bars and the peak lines fall, dB a second, and how long a peak holds, ms
let barFall = 30.
let peakFall = 15.
let peakHold = 1000.
// messages older than this are taken as silence, ms
let stale = 300.

// the clock requestAnimationFrame's times are on
@val external performanceNow: unit => float = "performance.now"

let decodeLevels = (json: JSON.t) =>
  switch json {
  | Number(x) => Some([x])
  | Array(xs) =>
    Some(
      xs->Array.map(x =>
        switch x {
        | JSON.Number(v) => v
        | _ => 0.
        }
      ),
    )
  | _ => None
  }

let make = (ctx: Ctx.t, parent, box: box, ~endpoint=?, ~channels=2, ~floor=-60., ~name="Level") => {
  let root = el("div", ~cls="meter", ~parent)->placeBox(box)
  let bars = Array.fromInitializer(~length=channels, _ => {
    let bar = el("div", ~cls="bar", ~parent=root)
    (bar, el("i", ~parent=bar), el("b", ~parent=bar))
  })
  let dbOf = Graph.gainDb
  // what the patch last said (dB), and when
  let target = Array.make(~length=channels, -120.)
  let received = ref(0.)
  // what is shown: the bars, the peaks (dB) and when each peak was set
  let level = Array.make(~length=channels, -120.)
  let peak = Array.make(~length=channels, -120.)
  let peakAt = Array.make(~length=channels, 0.)
  let lastFrame = ref(None)
  let running = ref(false)

  let percent = db => Float.toString(Float.clamp((db - floor) / -.floor, ~min=0., ~max=1.) * 100.) ++ "%"

  // over the meter, the status line follows the levels
  let status = ctx.status->Status.live(root, () => {
    let list = xs => xs->Array.map(db => Param.dbText(db))->Array.join(" / ")
    `${name}: ${list(level)}    peak ${list(peak)}    (click to reset the peaks)`
  })

  let show = () => {
    bars->Array.forEachWithIndex(((bar, fill, line), c) => {
      let (l, p) = (level->Array.getUnsafe(c), peak->Array.getUnsafe(c))
      fill->setStyle("height", percent(l))
      line->setStyle("bottom", percent(p))
      line->setStyle("display", p > floor ? "" : "none")
      bar->toggleClass("hot", p >= 0.)
    })
    status.refresh()
  }

  // one frame: the bars fall towards what the patch said (jump up to it), the peaks hold, then
  // fall; true while anything still moves
  let step = (now: float) => {
    let dt = switch lastFrame.contents {
    | Some(t) => Math.min(0.1, (now - t) / 1000.)
    | None => 0.
    }
    lastFrame := Some(now)
    let quiet = now - received.contents > stale
    let moving = ref(false)
    for c in 0 to channels - 1 {
      let want = quiet ? -120. : target->Array.getUnsafe(c)
      let l = level->Array.getUnsafe(c)
      let l = want >= l ? want : Math.max(want, l - barFall * dt)
      level->Array.setUnsafe(c, l)
      if l > want && l > floor {
        moving := true
      }
      let p = peak->Array.getUnsafe(c)
      if l >= p {
        peak->Array.setUnsafe(c, l)
        peakAt->Array.setUnsafe(c, now)
      } else if now - peakAt->Array.getUnsafe(c) > peakHold {
        peak->Array.setUnsafe(c, Math.max(l, p - peakFall * dt))
      }
      if peak->Array.getUnsafe(c) > Math.max(l, floor) {
        moving := true
      }
    }
    show()
    moving.contents
  }

  // (hidden while moving: the next message picks up from there)
  let interrupted = ref(false)
  let rec frame = now => {
    let moving = step(now)
    if moving && root->offsetParent->Option.isSome {
      requestAnimationFrame(frame)
    } else {
      interrupted := moving
      running := false
      lastFrame := None
    }
  }
  let wake = () =>
    if !running.contents {
      running := true
      requestAnimationFrame(frame)
    }

  // The patch sends levels some 30 times a second, silent or not: only a change (or the first
  // message after a quiet spell) needs a frame, and the bars drop once the messages stop.
  let staleTimer = ref(None)
  let feed = levels => {
    let now = performanceNow()
    let changed = ref(interrupted.contents || now - received.contents > stale)
    for c in 0 to channels - 1 {
      // a mono message feeds every bar
      let x = levels[c]->Option.orElse(levels[0])->Option.getOr(0.)
      let db = dbOf(Math.abs(x))
      if db != target->Array.getUnsafe(c) {
        changed := true
      }
      target->Array.setUnsafe(c, db)
    }
    received := now
    staleTimer.contents->Option.forEach(clearTimeout)
    staleTimer := Some(setTimeout(wake, Float.toInt(stale) + 20))
    if changed.contents {
      wake()
    }
  }

  let reset = () => {
    for c in 0 to channels - 1 {
      peak->Array.setUnsafe(c, level->Array.getUnsafe(c))
    }
    show()
  }

  root->onPointer(#pointerdown, ev =>
    if ev->button == 0 {
      reset()
    }
  )

  endpoint->Option.forEach(id =>
    ctx.pc->PatchConnection.addEndpointListener(id, json => decodeLevels(json)->Option.forEach(feed))
  )
  show()
  {root, reset, feed}
}
