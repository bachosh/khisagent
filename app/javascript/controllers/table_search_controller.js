import { Controller } from "@hotwired/stimulus"

// Filters table body rows by a free-text query (from khisfari).
// Non-matching rows get `.is-hidden`; the optional "empty" target shows when nothing matches.
export default class extends Controller {
  static targets = ["input", "row", "empty", "count"]

  filter() {
    const query = this.inputTarget.value.trim().toLowerCase()
    let shown = 0
    this.rowTargets.forEach((row) => {
      const match = query === "" || row.textContent.toLowerCase().includes(query)
      row.classList.toggle("is-hidden", !match)
      if (match) shown++
    })
    if (this.hasEmptyTarget) this.emptyTarget.hidden = shown > 0
    if (this.hasCountTarget) this.countTarget.textContent = shown
  }
}
