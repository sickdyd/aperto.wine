import { Controller } from "@hotwired/stimulus"

// Submits the form when an input inside it changes — used by the inline
// enable/disable toggles on the wine lists index.
export default class extends Controller {
  submit() {
    this.element.requestSubmit()
  }
}
