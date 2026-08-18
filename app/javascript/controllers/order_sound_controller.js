import { Controller } from "@hotwired/stimulus"

// The audible half of the order notification. The toast is the announcement;
// this is the thing that makes someone look at it — during service the screen
// at the pass is not being watched, it is being glanced at.
//
// Three decisions worth knowing before editing this file:
//
//   * The tone is synthesised, not loaded. Two oscillators and a gain envelope
//     cost nothing in the asset pipeline and raise no provenance question —
//     see docs/ASSETS.md for the bar an audio file would have had to clear.
//   * The preference lives in localStorage, per device, not on the account.
//     The tablet at the pass wants sound; the same owner's laptop at home at
//     23:00 does not, and they are the same login. A column could only hold
//     one answer for both.
//   * Browsers refuse to make a sound until the document has been interacted
//     with, so "the owner switched it on" and "this device can actually make a
//     noise" are two different facts. They are tracked separately and the
//     control shows the second one, because a toggle reading ON over a
//     silent room is the worst outcome this feature has available.

const STORAGE_KEY = "aperto.order-sound"

// Gestures that count as "the reader is here", used to lift a blocked context
// without making them find the toggle. Captured so a handler that stops
// propagation cannot hide the interaction from us.
const GESTURE_EVENTS = ["pointerdown", "keydown", "touchstart"]

// Several orders can land in one poll, and a poll can follow hard on the last
// one. One chime per burst; a rapid second is not more information.
const MIN_CHIME_GAP_MS = 1500

// A rising perfect fifth, G4 to D5, on triangle waves under a gentle lowpass:
// warm and wooden rather than the bright square-wave blip of a phone alert,
// and close enough to a struck object that it carries across a service room
// without asking for the whole room's attention. Total length ≈ 0.75s.
const CHIME = {
  notes: [
    { frequency: 392.0, at: 0 },
    { frequency: 587.33, at: 0.16 }
  ],
  attack: 0.014,
  decay: 0.55,
  peak: 0.16,
  cutoffHz: 2600
}

// One AudioContext per document, deliberately outside the controller. Turbo
// swaps pages without reloading, so every visit disconnects this controller
// and connects a fresh one; a context owned by the instance would be rebuilt
// on each navigation, and a newly built context starts suspended. Sound
// switched on at the start of service would then go silent the first time
// anyone clicked a nav link, with nothing to show for it.
let audioContext = null

function readPreference() {
  try {
    return window.localStorage.getItem(STORAGE_KEY) === "on"
  } catch {
    // Storage can be unavailable outright (Safari in some privacy modes).
    // Sound simply does not persist there; it must not take the page with it.
    return false
  }
}

function writePreference(enabled) {
  try {
    window.localStorage.setItem(STORAGE_KEY, enabled ? "on" : "off")
  } catch {
    // As above — the toggle still works for this document, it just forgets.
  }
}

// The envelope is shaped rather than switched. A gain that jumps between 0 and
// full is a step in the waveform, and a step is heard as a click at both ends
// of the note — which is most of what makes a synthesised tone sound cheap.
// Ramp in, decay exponentially (how a struck object actually dies away), then
// one short linear ramp to true zero, because exponentialRampToValueAtTime
// cannot reach it.
function playChime(context) {
  const start = context.currentTime + 0.01

  const filter = context.createBiquadFilter()
  filter.type = "lowpass"
  filter.frequency.value = CHIME.cutoffHz
  filter.connect(context.destination)

  CHIME.notes.forEach(({ frequency, at }) => {
    const openedAt = start + at
    const peakAt = openedAt + CHIME.attack
    const decayedAt = peakAt + CHIME.decay
    const closedAt = decayedAt + 0.02

    const oscillator = context.createOscillator()
    oscillator.type = "triangle"
    oscillator.frequency.value = frequency

    const gain = context.createGain()
    gain.gain.setValueAtTime(0, openedAt)
    gain.gain.linearRampToValueAtTime(CHIME.peak, peakAt)
    gain.gain.exponentialRampToValueAtTime(0.0008, decayedAt)
    gain.gain.linearRampToValueAtTime(0, closedAt)

    oscillator.connect(gain)
    gain.connect(filter)
    oscillator.start(openedAt)
    oscillator.stop(closedAt + 0.03)
  })
}

export default class extends Controller {
  static targets = ["toggle"]

  connect() {
    this.lastChimeAt = 0
    // A running context can be suspended again without anybody touching this
    // page — an iPad locking at the pass, a tab backgrounded on iOS. That is
    // the same predicament as a document that has never been interacted with,
    // so it gets the same answer: say so, and arm the listener that will lift
    // it on the next tap. Re-rendering alone would leave a control reading
    // "Allow sound" that only a direct press could ever repair.
    this.onStateChange = () => {
      this.watchForGesture()
      this.render()
    }
    this.onGesture = (event) => this.liftBlock(event)

    // Outside a restaurant the owner shell renders no toggle and there are no
    // orders to announce, so there is nothing for this controller to do.
    if (!this.hasToggleTarget) return

    if (audioContext) audioContext.addEventListener("statechange", this.onStateChange)
    if (this.enabled) this.watchForGesture()
    this.render()
  }

  disconnect() {
    this.stopWatchingForGesture()
    if (audioContext) audioContext.removeEventListener("statechange", this.onStateChange)
  }

  // ── State ────────────────────────────────────────────────────────────────
  //
  // "on" means a sound would actually be made. "blocked" means the owner asked
  // for sound and the browser has not granted this document audio yet — the
  // one state a naive implementation collapses into "on" and lies about.

  get enabled() {
    return readPreference()
  }

  get state() {
    if (!this.enabled) return "off"

    return audioContext?.state === "running" ? "on" : "blocked"
  }

  // ── The control ──────────────────────────────────────────────────────────

  // Turning it off is just the preference. Turning it on — or repairing a
  // blocked one — has to happen inside this call, because a click handler is
  // one of the few moments a browser will let audio start at all.
  toggle() {
    if (this.state === "on") {
      writePreference(false)
      this.render()
      return
    }

    writePreference(true)
    this.enable({ confirm: true })
  }

  async enable({ confirm }) {
    // Bringing a context up is asynchronous, and until it settles the state
    // still reads "blocked" — so a second press would run this whole body
    // again and, after its own await, pass the same confirmation check. Two
    // chimes for one activation. announce()'s debounce does not cover this
    // path, because a deliberate press should always be answered.
    if (this.enabling) return
    this.enabling = true

    try {
      // On iOS the hardware silent switch mutes Web Audio — but not <audio>
      // elements — because a page's audio session defaults to "ambient", which
      // respects the ringer. That is the difference between a chime and
      // silence on an iPad left face-up at the pass in silent mode, and it
      // fails the worst way available: the toggle would read "Sound on" while
      // the room hears nothing.
      //
      // Declaring the session as "playback" opts out of the ringer switch, the
      // same way a native app selects an AVAudioSession category. Only Safari
      // implements this today — which is exactly the browser that needs it —
      // and the spec is still an Editor's Draft, so it is feature-detected
      // rather than assumed.
      if ("audioSession" in navigator) navigator.audioSession.type = "playback"

      audioContext ||= new (window.AudioContext || window.webkitAudioContext)()
      audioContext.addEventListener("statechange", this.onStateChange)
      await audioContext.resume()
    } catch {
      // No Web Audio, or the browser declined. render() below reports what is
      // true rather than what was asked for, which is the entire point.
    } finally {
      this.enabling = false
    }

    // The confirmation chime is not decoration. Whether this dashboard, on
    // this device, at this volume, in this room, can be heard from the pass is
    // a question only a human standing there can answer — and they can only
    // answer it by hearing it once, on purpose.
    if (confirm && this.state === "on") this.chime()

    this.watchForGesture()
    this.render()
  }

  // ── Announcing ───────────────────────────────────────────────────────────

  // Fired by order_notifications_controller when a poll turns up an order it
  // had not seen before. Newness is decided there, against the same window of
  // ids the toast is drawn from — this file must never grow its own idea of
  // which orders are new, or the two would drift and the room would hear
  // announcements the screen never made.
  announce() {
    if (this.state !== "on") return

    const now = Date.now()
    if (now - this.lastChimeAt < MIN_CHIME_GAP_MS) return

    this.chime()
  }

  chime() {
    this.lastChimeAt = Date.now()
    try {
      playChime(audioContext)
    } catch {
      // A context torn down under us. Nothing to recover and nothing to say.
    }
  }

  // ── Recovering from a blocked context ────────────────────────────────────

  // With the preference on, the first interaction anywhere in the dashboard is
  // enough for the browser, so staff should not have to hunt for the toggle
  // after every full page load. Gestures on the toggle itself are ignored:
  // pointerdown precedes click, and lifting the block from here would leave
  // toggle() looking at an already-running context and reading the tap as
  // "turn it off" — the opposite of what was asked.
  liftBlock(event) {
    if (this.toggleTargets.some((toggle) => toggle.contains(event.target))) return
    if (!this.enabled) return

    this.enable({ confirm: false })
  }

  watchForGesture() {
    if (!this.enabled || this.state === "on") {
      this.stopWatchingForGesture()
      return
    }
    if (this.watching) return

    this.watching = true
    GESTURE_EVENTS.forEach((name) => document.addEventListener(name, this.onGesture, true))
  }

  stopWatchingForGesture() {
    if (!this.watching) return

    this.watching = false
    GESTURE_EVENTS.forEach((name) => document.removeEventListener(name, this.onGesture, true))
  }

  // ── Rendering ────────────────────────────────────────────────────────────

  // One attribute, and the stylesheet picks the face. No markup is built here
  // and no class name is assembled anywhere — Tailwind only emits rules for
  // literal strings it can find in the source.
  render() {
    this.toggleTargets.forEach((toggle) => {
      toggle.dataset.soundState = this.state
      toggle.setAttribute("aria-pressed", this.state === "on" ? "true" : "false")
    })
  }
}
