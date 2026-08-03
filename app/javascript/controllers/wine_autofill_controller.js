import { Controller } from "@hotwired/stimulus"

// Type-ahead on the wine name field. Queries the owner wine_lookups proxy and
// fills the descriptive fields when the owner picks a suggestion. Any fetch
// problem simply leaves the dropdown closed — manual entry must never break.
export default class extends Controller {
  static targets = ["input", "results", "producer", "grape", "vintage", "region", "color"]
  static values = { url: String, minChars: { type: Number, default: 3 }, delay: { type: Number, default: 350 } }

  disconnect() {
    this.#reset()
  }

  search() {
    clearTimeout(this.timeout)
    const query = this.inputTarget.value.trim()
    if (query.length < this.minCharsValue) {
      this.#close()
      return
    }
    this.timeout = setTimeout(() => this.#fetchSuggestions(query), this.delayValue)
  }

  close(event) {
    // Keep the dropdown open when focus moves into one of its buttons.
    // Belt-and-braces: Safari doesn't focus a <button> on click, so
    // relatedTarget alone can't be trusted there — see keepOpen().
    if (event?.relatedTarget && this.resultsTarget.contains(event.relatedTarget)) return
    this.#close()
  }

  // Safari doesn't move focus to a clicked <button> until after mousedown,
  // so the input's blur fires (and empties the dropdown) before the click
  // handler runs. Suppressing the default mousedown behavior stops the
  // input from losing focus in the first place, in every browser.
  keepOpen(event) {
    event.preventDefault()
  }

  navigate(event) {
    const buttons = this.#suggestionButtons()
    if (buttons.length === 0) return

    switch (event.key) {
      case "ArrowDown":
      case "ArrowUp": {
        event.preventDefault()
        const step = event.key === "ArrowDown" ? 1 : -1
        const next = (this.activeIndex + step + buttons.length) % buttons.length
        this.#highlight(buttons, next)
        break
      }
      case "Enter":
        if (this.activeIndex >= 0) {
          event.preventDefault()
          buttons[this.activeIndex].click()
        }
        break
      case "Escape":
        this.#close()
        break
    }
  }

  select(event) {
    const wine = JSON.parse(event.currentTarget.dataset.wine)
    this.#fill(this.inputTarget, wine.name)
    this.#fill(this.producerTarget, wine.producer)
    this.#fill(this.grapeTarget, wine.grape_variety)
    this.#fill(this.vintageTarget, wine.vintage_year)
    this.#fill(this.regionTarget, wine.region)
    if (wine.color) this.colorTarget.value = wine.color
    this.#close()
    this.inputTarget.focus()
  }

  async #fetchSuggestions(query) {
    this.abortController?.abort()
    this.abortController = new AbortController()

    try {
      const url = new URL(this.urlValue, window.location.origin)
      url.searchParams.set("q", query)
      const response = await fetch(url, {
        headers: { Accept: "application/json" },
        signal: this.abortController.signal
      })
      if (!response.ok) {
        this.#close()
        return
      }
      this.#render(await response.json())
    } catch (error) {
      if (error.name !== "AbortError") this.#close()
    }
  }

  #render(wines) {
    if (wines.length === 0) {
      this.#close()
      return
    }
    const items = wines.map((wine, index) => {
      const label = this.#label(wine)
      const item = document.createElement("li")
      const button = document.createElement("button")
      button.type = "button"
      button.id = `wine-suggestion-${index}`
      button.className = "w-full text-left px-4 py-2 hover:bg-base-200 font-body text-sm"
      button.textContent = label
      button.dataset.wine = JSON.stringify(wine)
      button.dataset.action = "wine-autofill#select"
      button.setAttribute("role", "option")
      button.setAttribute("aria-selected", "false")
      item.appendChild(button)
      return item
    })
    this.resultsTarget.replaceChildren(...items)
    this.resultsTarget.classList.remove("hidden")
    this.inputTarget.setAttribute("aria-expanded", "true")
    this.activeIndex = -1
  }

  // The vintage is a guess (the newest one on record) that select() writes into
  // the form, so it belongs in the label — otherwise the owner cannot see what
  // is about to be filled in.
  #label(wine) {
    let label = wine.name
    if (wine.vintage_year) label += ` ${wine.vintage_year}`
    if (wine.producer) label += ` — ${wine.producer}`
    if (wine.region) label += ` (${wine.region})`
    return label
  }

  #suggestionButtons() {
    return Array.from(this.resultsTarget.querySelectorAll("button"))
  }

  #highlight(buttons, index) {
    buttons.forEach((button, i) => {
      const active = i === index
      button.classList.toggle("bg-base-200", active)
      button.setAttribute("aria-selected", active ? "true" : "false")
    })
    this.activeIndex = index
    const active = buttons[index]
    if (active) {
      this.inputTarget.setAttribute("aria-activedescendant", active.id)
    } else {
      this.inputTarget.removeAttribute("aria-activedescendant")
    }
  }

  #fill(target, value) {
    if (value !== null && value !== undefined && value !== "") target.value = value
  }

  #close() {
    // Cancel pending work first: a queued debounce timer or in-flight fetch
    // would otherwise reopen the dropdown right after it was dismissed.
    this.#reset()
    this.resultsTarget.replaceChildren()
    this.resultsTarget.classList.add("hidden")
    this.inputTarget.setAttribute("aria-expanded", "false")
    this.inputTarget.removeAttribute("aria-activedescendant")
    this.activeIndex = -1
  }

  #reset() {
    clearTimeout(this.timeout)
    this.abortController?.abort()
  }
}
