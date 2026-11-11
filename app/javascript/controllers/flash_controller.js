import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="flash". Notices fade out by themselves; alerts stay until closed.
export default class extends Controller {
  connect() {
    if (this.element.classList.contains("flash-message--notice")) {
      this.timeout = setTimeout(() => this.close(), 6000)
    }
  }

  disconnect() {
    clearTimeout(this.timeout)
  }

  close() {
    this.element.remove()
  }
}
