import { Controller } from "@hotwired/stimulus"

// "PDF / Print" button on the report page (print styles hide the navigation)
export default class extends Controller {
  print() {
    window.print()
  }
}
