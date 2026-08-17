import { Controller } from "@hotwired/stimulus"

const DEBOUNCE_MS = 150

// Instant client-side substring filter, shared by the owner wines index, the
// list-builder "Available wines" column, the owner wine lists index, and the
// public menu.
//
// `item` elements carry a pre-downcased `data-search-terms` attribute and, on
// pages that also offer facet chips, one `data-facet-<name>` attribute per
// facet the item takes a value on (space- or pipe-separated for an item that
// carries more than one value in that facet, e.g. offering both servings).
// `facet` targets are `aria-pressed` toggle buttons carrying `data-facet-name`
// and `data-facet-value`; an item matches a facet name once any selection is
// active on it only if its own value list intersects the selected ones —
// facets AND across names, OR within a name. Neither the item nor the facet
// dataset is ever mutated here — only visibility (and a chip's aria-pressed)
// is toggled, as the controller already documents.
//
// `group` wraps a set of items (e.g. a colour section) and hides as a whole
// once none of its items match. `clear` is an optional control shown only
// while a text term or a facet selection is active.
//
// On the public menu the facet chips sit inside a collapsed disclosure —
// `panel`, toggled by the `disclosure` button — so the wine list rather than a
// screenful of filter chrome is what a diner meets first. `count` and
// `countLabel` are the applied tally the trigger carries: the visible badge
// and its screen-reader wording, written together, so collapsing the panel
// never hides the fact that a filter is on. The disclosure is a disclosure and
// not a dialog — the panel follows its trigger in the DOM, so there is nothing
// to trap and no focus to restore.
//
// A page with no `facet`/`clear` targets and no `data-facet-*` attributes
// behaves exactly as before: `activeFacetsByName` returns an empty map, so
// every item passes the (vacuous) facet check. The disclosure targets are
// equally optional — the owner pages that share this controller have none.
export default class extends Controller {
  static targets = [
    "input", "item", "group", "empty", "facet", "clear",
    "disclosure", "panel", "count", "countLabel"
  ]

  // The screen-reader wording for the applied tally, e.g. "Filters applied:
  // %{count}". Interpolated here rather than pluralised in the view because
  // the count is only known once a chip is pressed; the phrasing is chosen in
  // both locales to read correctly for any number, one included.
  static values = { appliedLabel: { type: String, default: "" } }

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

  // A chip tap applies immediately — only the text input debounces.
  toggleFacet(event) {
    const chip = event.currentTarget
    const pressed = chip.getAttribute("aria-pressed") === "true"
    chip.setAttribute("aria-pressed", pressed ? "false" : "true")
    this.apply()
  }

  clearAll() {
    if (this.hasInputTarget) this.inputTarget.value = ""
    this.facetTargets.forEach((chip) => chip.setAttribute("aria-pressed", "false"))
    this.apply()
  }

  // Opens or closes the facet panel. Only visibility and aria-expanded change:
  // a collapsed panel keeps whatever is pressed inside it, which is why the
  // trigger has to carry the count.
  toggleFilters() {
    if (!this.hasPanelTarget || !this.hasDisclosureTarget) return

    const expanded = this.disclosureTarget.getAttribute("aria-expanded") === "true"
    this.disclosureTarget.setAttribute("aria-expanded", expanded ? "false" : "true")
    this.panelTarget.hidden = expanded
  }

  apply() {
    const term = this.hasInputTarget ? this.inputTarget.value.trim().toLowerCase() : ""
    const activeFacets = this.activeFacetsByName()
    let visibleCount = 0

    this.itemTargets.forEach((item) => {
      const matchesTerm = term === "" || (item.dataset.searchTerms || "").includes(term)
      const matchesFacets = this.itemMatchesFacets(item, activeFacets)
      const matches = matchesTerm && matchesFacets
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

    if (this.hasClearTarget) {
      const anyActive = term !== "" || activeFacets.size > 0
      this.clearTarget.hidden = !anyActive
    }

    this.renderAppliedCount()
  }

  // The tally on the disclosure trigger: how many facet chips are pressed,
  // counted across every facet rather than per facet, because that is the
  // question a collapsed panel leaves open. The text term is deliberately not
  // counted — it is still visible in the search field beside the trigger.
  renderAppliedCount() {
    if (!this.hasCountTarget) return

    const pressed = this.facetTargets.filter(
      (chip) => chip.getAttribute("aria-pressed") === "true"
    ).length

    this.countTarget.hidden = pressed === 0
    this.countTarget.textContent = pressed === 0 ? "" : String(pressed)

    if (this.hasCountLabelTarget) {
      // replaceAll, not replace: a locale is free to repeat the placeholder,
      // and substituting only the first one would leave "%{count}" to be read
      // out verbatim. textContent, never innerHTML — the label is text.
      this.countLabelTarget.textContent =
        pressed === 0 ? "" : this.appliedLabelValue.replaceAll("%{count}", String(pressed))
    }
  }

  // { facetName => Set(selectedValues) }, built from every pressed chip.
  // Empty when there are no facet targets at all, or none is pressed.
  activeFacetsByName() {
    const active = new Map()

    this.facetTargets.forEach((chip) => {
      if (chip.getAttribute("aria-pressed") !== "true") return

      const name = chip.dataset.facetName
      const value = chip.dataset.facetValue
      if (!active.has(name)) active.set(name, new Set())
      active.get(name).add(value)
    })

    return active
  }

  itemMatchesFacets(item, activeFacets) {
    for (const [ name, values ] of activeFacets) {
      const itemValues = (item.getAttribute(`data-facet-${name}`) || "").split(/[\s|]+/).filter(Boolean)
      if (!itemValues.some((value) => values.has(value))) return false
    }

    return true
  }
}
