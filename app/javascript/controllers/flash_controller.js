import { Controller } from "@hotwired/stimulus"

// Must match the transition on .toast-leaving in the stylesheet: the band is
// removed one fade after the class lands, so the removal is not visible as a cut.
const FADE_MS = 180

// A floating flash band. It dismisses itself after `timeout` milliseconds, or
// immediately when the close button is pressed.
//
// timeout = 0 means "stay until dismissed". The partial passes 0 under test,
// where a band that removed itself mid-assertion would make every flash
// system test a coin flip.
export default class extends Controller {
  static values = { timeout: { type: Number, default: 6000 } }

  connect() {
    if (this.timeoutValue > 0) {
      this.dismissTimer = setTimeout(() => this.dismiss(), this.timeoutValue)
    }
  }

  // Turbo swaps the page without a reload, and a Turbo Stream can replace the
  // whole flash target. Either leaves a timer running against an element that
  // is no longer in the document.
  disconnect() {
    this.clearTimers()
  }

  dismiss() {
    this.clearTimers()
    this.element.classList.add("toast-leaving")
    this.removalTimer = setTimeout(() => this.element.remove(), FADE_MS)
  }

  clearTimers() {
    clearTimeout(this.dismissTimer)
    clearTimeout(this.removalTimer)
  }
}
