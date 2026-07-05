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
    if (event?.relatedTarget && this.resultsTarget.contains(event.relatedTarget)) return
    this.#close()
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
    const items = wines.map((wine) => {
      const label = [wine.name, wine.region].filter(Boolean).join(" — ")
      const item = document.createElement("li")
      const button = document.createElement("button")
      button.type = "button"
      button.className = "w-full text-left px-4 py-2 hover:bg-base-200 font-body text-sm"
      button.textContent = label
      button.dataset.wine = JSON.stringify(wine)
      button.dataset.action = "wine-autofill#select"
      item.appendChild(button)
      return item
    })
    this.resultsTarget.replaceChildren(...items)
    this.resultsTarget.classList.remove("hidden")
    this.inputTarget.setAttribute("aria-expanded", "true")
    this.activeIndex = -1
  }

  #suggestionButtons() {
    return Array.from(this.resultsTarget.querySelectorAll("button"))
  }

  #highlight(buttons, index) {
    buttons.forEach((button, i) => button.classList.toggle("bg-base-200", i === index))
    this.activeIndex = index
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
    this.activeIndex = -1
  }

  #reset() {
    clearTimeout(this.timeout)
    this.abortController?.abort()
  }
}
