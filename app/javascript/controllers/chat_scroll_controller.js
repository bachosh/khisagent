import { Controller } from "@hotwired/stimulus"

// Keeps the chat scrolled to the newest message while the user is near the bottom
export default class extends Controller {
  static targets = ["list"]

  connect() {
    this.element.scrollTop = this.element.scrollHeight
    this.observer = new MutationObserver(() => {
      if (this.nearBottom || this.justSent) this.element.scrollTop = this.element.scrollHeight
      this.justSent = false
    })
    this.observer.observe(this.listTarget, { childList: true, subtree: true, characterData: true })
    this.element.addEventListener("scroll", () => {
      this.nearBottom = this.element.scrollHeight - this.element.scrollTop - this.element.clientHeight < 160
    })
    this.nearBottom = true
    this.onSubmit = () => { this.justSent = true }
    document.addEventListener("turbo:submit-start", this.onSubmit)
  }

  disconnect() {
    this.observer?.disconnect()
    document.removeEventListener("turbo:submit-start", this.onSubmit)
  }
}
