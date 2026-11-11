import { Controller } from "@hotwired/stimulus"

// <details> dropdown that closes on an outside click or Escape
export default class extends Controller {
  closeOutside(event) {
    if (!this.element.contains(event.target)) this.close()
  }

  close() {
    this.element.removeAttribute("open")
  }
}
