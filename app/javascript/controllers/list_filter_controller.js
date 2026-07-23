import { Controller } from "@hotwired/stimulus"

const DEBOUNCE_MS = 150

// Instant client-side substring filter, shared by the owner wines index, the
// list-builder "Available wines" column, and the owner wine lists index.
//
// `item` elements carry a pre-downcased `data-search-terms` attribute (never
// mutated here — only visibility is toggled). `group` wraps a set of items
// (e.g. a color section) and hides as a whole once none of its items match.
export default class extends Controller {
  static targets = ["input", "item", "group", "empty", "count"]

  connect() {
    this.timeout = null
  }

  disconnect() {
    clearTimeout(this.timeout)
  }

  filter() {
    clearTimeout(this.timeout)
    this.timeout = setTimeout(() => this.apply(), DEBOUNCE_MS)
  }

  apply() {
    const term = this.inputTarget.value.trim().toLowerCase()
    let visibleCount = 0

    this.itemTargets.forEach((item) => {
      const matches = term === "" || (item.dataset.searchTerms || "").includes(term)
      item.hidden = !matches
      if (matches) visibleCount += 1
    })

    this.groupTargets.forEach((group) => {
      const items = group.querySelectorAll("[data-list-filter-target~='item']")
      group.hidden = !Array.from(items).some((item) => !item.hidden)
    })

    if (this.hasEmptyTarget) {
      this.emptyTarget.hidden = this.itemTargets.length === 0 || visibleCount > 0
    }

    if (this.hasCountTarget) {
      this.countTarget.textContent = visibleCount
    }
  }
}
