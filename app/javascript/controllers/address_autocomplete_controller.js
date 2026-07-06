import { Controller } from "@hotwired/stimulus"

// Companion to stimulus-autocomplete on the owner address field: copies the
// picked suggestion's coordinates into hidden latitude/longitude fields and
// clears them when the address is edited by hand — the server then
// re-geocodes on save (see Restaurant#geocode_address).
export default class extends Controller {
  static targets = ["latitude", "longitude"]

  select(event) {
    const selected = event.detail.selected
    if (!selected) return

    this.latitudeTarget.value = selected.dataset.latitude || ""
    this.longitudeTarget.value = selected.dataset.longitude || ""
  }

  clear() {
    this.latitudeTarget.value = ""
    this.longitudeTarget.value = ""
  }
}
