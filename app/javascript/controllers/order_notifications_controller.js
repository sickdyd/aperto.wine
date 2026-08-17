import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"

// The server names the window it just handed over in this header; the next
// request sends it straight back as `known`. That is the whole protocol — no
// per-tab state on the server, and no cursor arithmetic here that could drift.
const WINDOW_HEADER = "X-Order-Window"

// Asks the server, on a timer, whether an order has arrived — and lets the
// server answer in Turbo Streams, so what a new order looks like stays in ERB
// and this file never renders anything.
//
// Two things it deliberately does not do:
//
//   * poll a hidden tab. A dashboard left open overnight on a locked screen
//     would otherwise spend the night asking; there is also nothing to see, and
//     the toasts would all be waiting in a pile on return. Coming back triggers
//     an immediate poll instead, so the pile is one round of genuinely current
//     news.
//   * treat a failed poll as anything at all. The owner cannot act on "the
//     network blinked", and a poller that starts reporting its own health is
//     noisier than the thing it is reporting on. The next tick just tries again.
export default class extends Controller {
  // badgeId comes from the page rather than being spelled out again here: the
  // markup and the Ruby constant behind it are the one source of that name, and
  // a copy in this file could drift out of sync without anything failing.
  static values = {
    url: String,
    badgeId: String,
    interval: { type: Number, default: 15000 },
    known: Array
  }

  connect() {
    this.known = this.knownValue.map(Number)
    this.onVisibilityChange = () => this.resync()
    document.addEventListener("visibilitychange", this.onVisibilityChange)
    this.schedule()
  }

  // Turbo swaps pages without a reload, so without this every navigation would
  // leave another timer running against a detached element.
  disconnect() {
    document.removeEventListener("visibilitychange", this.onVisibilityChange)
    clearTimeout(this.timer)
  }

  resync() {
    if (document.hidden) {
      clearTimeout(this.timer)
    } else {
      this.schedule(0)
    }
  }

  schedule(delay = this.intervalValue) {
    clearTimeout(this.timer)
    this.timer = setTimeout(() => this.poll(), delay)
  }

  async poll() {
    if (document.hidden) return

    try {
      const response = await fetch(this.pollUrl(), {
        headers: { Accept: "text/vnd.turbo-stream.html" },
        credentials: "same-origin"
      })

      if (response.ok) {
        this.rememberWindow(response.headers.get(WINDOW_HEADER))
      }
      // 204 is the server saying nothing has moved; only a 200 carries markup.
      if (response.status === 200) {
        Turbo.renderStreamMessage(await response.text())
      }
    } catch {
      // See the note above: a dropped poll is not news.
    }

    this.schedule()
  }

  pollUrl() {
    const url = new URL(this.urlValue, window.location.origin)
    url.searchParams.set("count", this.pendingCount())
    this.known.forEach((id) => url.searchParams.append("known[]", id))
    return url
  }

  // An empty header is a restaurant with no orders at all, which is a real
  // answer; a missing one means the response never got that far, so the window
  // this tab is holding stands.
  rememberWindow(header) {
    if (header === null) return

    this.known = header.split(",").filter(Boolean).map(Number)
  }

  // Read back off the page rather than tracked here, so a badge replaced by any
  // other response is still the one the next poll reports.
  pendingCount() {
    return document.getElementById(this.badgeIdValue)?.dataset.pendingCount ?? ""
  }
}
