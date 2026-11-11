import { Controller } from "@hotwired/stimulus"

// The big "drop your statement" area on a new chat: opens the composer's file picker
export default class extends Controller {
  open() {
    document.querySelector("[data-composer-target='files']")?.click()
  }
}
