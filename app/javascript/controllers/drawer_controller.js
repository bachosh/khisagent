import { Controller } from "@hotwired/stimulus"

// Mobile drawers: the left nav (chat history) and the right nav (insights). Lives on <body>.
export default class extends Controller {
  toggleSidebar() {
    this.element.classList.toggle("sidebar-open")
  }

  toggleInsights() {
    this.element.classList.toggle("insights-open")
  }

  close() {
    this.element.classList.remove("sidebar-open", "insights-open")
  }
}
