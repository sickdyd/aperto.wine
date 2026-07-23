import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"
import Sortable from "sortablejs"

// Drag-and-drop for the wine list builder. Enhances the always-working button
// controls (Add to list / delete / sort-order field) — never replaces them.
//
// Two SortableJS instances share the "wine-list" group:
//   - members  : reorder rows (onUpdate -> PATCH sort) and receive clones from
//                the available column (onAdd -> POST create).
//   - available: source only (pull clone, put false, sort false).
//
// This element is the turbo_stream replace target, so Stimulus re-connects
// after every server repaint and rebuilds the instances cleanly.
export default class extends Controller {
  static targets = ["members", "available"]
  static values = { createUrl: String, sortUrl: String }

  connect() {
    this.sortables = []

    if (this.hasMembersTarget) {
      this.sortables.push(new Sortable(this.membersTarget, {
        group: "wine-list",
        handle: "[data-sortable-handle]",
        animation: 150,
        onStart: () => { this.snapshot = this.memberIds() },
        onUpdate: () => this.persistOrder(),
        onAdd: (event) => this.addWine(event)
      }))
    }

    if (this.hasAvailableTarget) {
      this.sortables.push(new Sortable(this.availableTarget, {
        group: { name: "wine-list", pull: "clone", put: false },
        sort: false,
        // Keep interactive controls clickable instead of starting a drag.
        filter: "a, button, input, [data-sortable-handle]",
        // Don't preventDefault() on touchstart for filtered elements — that
        // would swallow the synthesized click on the "Add to list" button,
        // the mobile fallback for drag-and-drop.
        preventOnFilter: false,
        // Rows aren't touch-action: none here (unlike member rows, which
        // scope that to their drag handle), so a bare touchstart must be
        // able to become a scroll. Require a brief hold before a drag
        // starts, and a small movement threshold, so taps/swipes pass
        // through untouched.
        delay: 150,
        delayOnTouchOnly: true,
        touchStartThreshold: 5,
        animation: 150
      }))
    }
  }

  disconnect() {
    this.sortables.forEach((sortable) => sortable.destroy())
    this.sortables = []
  }

  // Persist a within-list reorder. Reverts the DOM to the pre-drag order if the
  // server rejects it.
  async persistOrder() {
    try {
      const response = await this.request(this.sortUrlValue, "PATCH", {
        item_ids: this.memberIds()
      })
      if (!response.ok) throw new Error(`sort failed: ${response.status}`)
    } catch (error) {
      this.restoreSnapshot()
      this.flash(this.data.get("reorderFailedMessage"))
    }
  }

  // A wine was dropped in from the available column. Remove the temporary clone
  // and let the server turbo_stream repaint the members container.
  async addWine(event) {
    const wineId = event.item.dataset.wineId
    event.item.remove()
    if (!wineId) return

    try {
      const response = await this.request(this.createUrlValue, "POST", {
        wine_id: wineId
      })
      const body = await response.text()
      if (response.ok || response.status === 422) {
        Turbo.renderStreamMessage(body)
      } else {
        throw new Error(`create failed: ${response.status}`)
      }
    } catch (error) {
      this.flash(this.data.get("addFailedMessage"))
    }
  }

  request(url, method, payload) {
    return fetch(url, {
      method: method,
      headers: {
        "Content-Type": "application/json",
        "Accept": "text/vnd.turbo-stream.html",
        "X-CSRF-Token": this.csrfToken()
      },
      body: JSON.stringify(payload),
      credentials: "same-origin"
    })
  }

  memberIds() {
    return Array.from(this.membersTarget.children)
      .map((row) => row.dataset.id)
      .filter(Boolean)
  }

  restoreSnapshot() {
    if (!this.snapshot) return
    const byId = new Map(
      Array.from(this.membersTarget.children).map((row) => [row.dataset.id, row])
    )
    this.snapshot.forEach((id) => {
      const row = byId.get(id)
      if (row) this.membersTarget.appendChild(row)
    })
  }

  flash(message) {
    if (message) window.alert(message)
  }

  csrfToken() {
    return document.querySelector("meta[name='csrf-token']")?.content || ""
  }
}
