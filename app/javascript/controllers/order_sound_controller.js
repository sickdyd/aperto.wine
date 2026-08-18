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
//
// THE CONTROL AND THE CHIME ARE SEPARATE, and that separation is the thing to
// be careful with when editing this file. There is exactly one control — a
// field on the restaurant settings page — and every other owner page has none,
// including the orders board, which is the screen this whole feature exists
// for. So the chime cannot be conditional on a toggle target being present.
// This controller is mounted on the owner shell, connects on every page of it,
// and takes its answer from localStorage; the toggle target is only ever a
// display of that answer, and `render()` over zero of them is a no-op by
// design, not by accident.
//
// Which is why connect() has no early return for a page without one. The
// pages with no control are precisely the ones that must still arm the gesture
// listener, repair a suspended context and answer announce() — that early
// return, kept unchanged, would have silenced everything except the settings
// page. Outside a restaurant (the restaurant index, the new-restaurant form)
// there is genuinely nothing to announce, and arming there is pointless; it is
// left armed anyway, because the AudioContext is per document and survives the
// Turbo visit into a restaurant, so a click on the index is a gesture already
// spent — and the alternative guard, sniffing for the poller's element in a
// sibling of this one, would couple the two controllers by page shape to save
// three listeners that disconnect() already removes.
//
// And one limitation to know before deploying this, inherited from the poller
// and deliberately not worked around here: this alerts a *visible* dashboard,
// not a backgrounded one. order_notifications_controller does not poll a
// hidden tab — read its reasoning, it is sound — so a dashboard behind another
// tab, minimised, or on a locked screen produces no toast and no chime, and
// returning to it announces the backlog in one round. The tablet at the pass,
// which is the deployment this serves, is visible; a laptop with the dashboard
// buried behind other windows is not, and must not be relied on to make a
// noise.

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

// Safari before the Audio Session API has no way to say "this is playback, not
// ambient", so its Web Audio output stays tied to the ringer switch — an iPad
// in silent mode at the pass hears nothing, which is the exact failure the
// three-state control exists to prevent, arriving by a route the control
// cannot detect.
//
// The pre-API workaround still works and is what feross/unmute-ios-audio does:
// play a few milliseconds of silence through an <audio> element inside the
// user's gesture. Media elements are not governed by the ringer switch, and
// starting one moves the page's audio session off "ambient" — after which Web
// Audio plays through the switch too.
//
// The clip is built here rather than pasted in as a base64 blob so that "this
// is silence and nothing else" can be read rather than taken on trust: a WAV
// header followed by 50 ms of the 8-bit zero line.
const SILENCE_RATE_HZ = 8000
const SILENCE_SAMPLES = SILENCE_RATE_HZ / 20

function silentClipUrl() {
  const bytes = new Uint8Array(44 + SILENCE_SAMPLES)
  const view = new DataView(bytes.buffer)
  const ascii = (at, text) => [...text].forEach((char, i) => view.setUint8(at + i, char.charCodeAt(0)))

  ascii(0, "RIFF")
  view.setUint32(4, 36 + SILENCE_SAMPLES, true)
  ascii(8, "WAVEfmt ")
  view.setUint32(16, 16, true)   // PCM header length
  view.setUint16(20, 1, true)    // format: uncompressed PCM
  view.setUint16(22, 1, true)    // mono
  view.setUint32(24, SILENCE_RATE_HZ, true)
  view.setUint32(28, SILENCE_RATE_HZ, true)
  view.setUint16(32, 1, true)    // block align
  view.setUint16(34, 8, true)    // bits per sample
  ascii(36, "data")
  view.setUint32(40, SILENCE_SAMPLES, true)
  bytes.fill(128, 44)            // 8-bit unsigned PCM: 128 is the zero line

  return `data:audio/wav;base64,${btoa(String.fromCharCode(...bytes))}`
}

// Built once per document and reused: the element is cheap to keep and
// rebuilding it would throw away whatever activation it has already earned.
let silentClip = null

// Called inside a user gesture, and only ever there. Answers the ringer switch
// by whichever route this browser offers: the standard one where it exists,
// the media-element trick where it does not. Everywhere that is neither iOS
// nor Safari this is a 50 ms silent play that changes nothing, which is
// cheaper than sniffing the platform to find out.
function releaseRingerSwitch() {
  // Both halves are contained, and separately. This is a courtesy to one
  // platform, while the caller goes on to bring up the AudioContext that
  // everything else depends on — a throw escaping here would trade a silenced
  // iPad for a feature that works nowhere at all.
  try {
    if ("audioSession" in navigator) {
      navigator.audioSession.type = "playback"
      return
    }
  } catch {
    // The property is there but would not take the assignment. Fall through to
    // the older remedy rather than treat a half-implemented API as an answer.
  }

  try {
    silentClip ||= new Audio(silentClipUrl())

    // Deliberately no currentTime reset before this. play() already seeks a
    // finished element back to the start, and assigning currentTime before
    // metadata has loaded throws on exactly the old WebKit this branch exists
    // for — which would abort the remedy one line before it ran, on the only
    // devices that need it.
    silentClip.play()?.catch(() => {
      // Refused, which means this gesture was not one the browser accepted.
      // Nothing to recover: the state the control reports is read off the
      // AudioContext either way, so it will say "blocked" rather than lie.
    })
  } catch {
    // A device with neither the API nor a usable media element is simply one
    // its own ringer switch will silence. The control still reports what the
    // context says, which is the guarantee that actually matters.
  }
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

    // No guard on hasToggleTarget: see the head of this file. Almost every
    // owner page has no control, and those are exactly the pages that still
    // have to be able to make a noise.
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
      // First, and inside the gesture: the ringer switch. On iOS it mutes Web
      // Audio while leaving <audio> alone, so an iPad face-up at the pass in
      // silent mode would otherwise hear nothing while the toggle read "Sound
      // on" — the worst outcome available here, arriving by a route the
      // control cannot detect.
      releaseRingerSwitch()

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
  // enough for the browser, so staff should not have to hunt for the settings
  // page after every full page load — which, now that the control lives there
  // and nowhere else, is the difference between a working feature and one that
  // has to be re-armed from another screen before the pass can hear anything.
  //
  // Gestures on the control itself are ignored: pointerdown precedes click, and
  // lifting the block from here would leave toggle() looking at an already-
  // running context and reading the tap as "turn it off" — the opposite of what
  // was asked. On the pages that carry no control there is nothing to exclude
  // and `some` over no targets is false, so every gesture counts.
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
  //
  // On every owner page but the settings one there is no target and this loops
  // over nothing. That is the right answer rather than a case to guard: the
  // state is held in localStorage and in the AudioContext, so a page with
  // nothing to draw has nothing to do here and everything else still works.
  render() {
    this.toggleTargets.forEach((toggle) => {
      toggle.dataset.soundState = this.state
      toggle.setAttribute("aria-pressed", this.state === "on" ? "true" : "false")
    })
  }
}
