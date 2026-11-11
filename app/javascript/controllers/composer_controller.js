import { Controller } from "@hotwired/stimulus"

// Chat composer: autosizing textarea, Enter to send (Shift+Enter = new line),
// file chips, drag & drop anywhere on the chat, suggestion buttons.
export default class extends Controller {
  static targets = ["input", "files", "chips", "send", "box"]
  static values = { maxFiles: { type: Number, default: 5 } }

  connect() {
    this.dt = new DataTransfer()
    this.dragDepth = 0
    this.onDragEnter = this.dragEnter.bind(this)
    this.onDragLeave = this.dragLeave.bind(this)
    this.onDragOver = (e) => e.preventDefault()
    this.onDrop = this.drop.bind(this)
    document.addEventListener("dragenter", this.onDragEnter)
    document.addEventListener("dragleave", this.onDragLeave)
    document.addEventListener("dragover", this.onDragOver)
    document.addEventListener("drop", this.onDrop)
    this.resize()
    this.update()
  }

  disconnect() {
    document.removeEventListener("dragenter", this.onDragEnter)
    document.removeEventListener("dragleave", this.onDragLeave)
    document.removeEventListener("dragover", this.onDragOver)
    document.removeEventListener("drop", this.onDrop)
  }

  keydown(event) {
    if (event.key === "Enter" && !event.shiftKey && !event.isComposing) {
      event.preventDefault()
      if (!this.sendTarget.disabled) this.element.requestSubmit()
    }
  }

  resize() {
    const input = this.inputTarget
    input.style.height = "auto"
    input.style.height = `${Math.min(input.scrollHeight, 220)}px`
    this.update()
  }

  pick() {
    this.add(Array.from(this.filesTarget.files))
  }

  add(files) {
    for (const file of files) {
      if (this.dt.files.length >= this.maxFilesValue) break
      if (Array.from(this.dt.files).some((f) => f.name === file.name && f.size === file.size)) continue
      this.dt.items.add(file)
    }
    this.filesTarget.files = this.dt.files
    this.renderChips()
    this.update()
    this.inputTarget.focus()
  }

  remove(event) {
    const index = Number(event.currentTarget.dataset.index)
    const next = new DataTransfer()
    Array.from(this.dt.files).forEach((f, i) => { if (i !== index) next.items.add(f) })
    this.dt = next
    this.filesTarget.files = this.dt.files
    this.renderChips()
    this.update()
  }

  renderChips() {
    this.chipsTarget.innerHTML = ""
    Array.from(this.dt.files).forEach((file, i) => {
      const chip = document.createElement("div")
      chip.className = "composer__chip"
      const name = document.createElement("span")
      name.textContent = `${file.name} · ${this.size(file.size)}`
      const button = document.createElement("button")
      button.type = "button"
      button.dataset.index = i
      button.dataset.action = "composer#remove"
      button.setAttribute("aria-label", `× ${file.name}`)
      button.textContent = "×"
      chip.append(name, button)
      this.chipsTarget.append(chip)
    })
  }

  size(bytes) {
    if (bytes < 1024 * 1024) return `${Math.max(1, Math.round(bytes / 1024))} KB`
    return `${(bytes / 1024 / 1024).toFixed(1)} MB`
  }

  suggest(event) {
    this.inputTarget.value = event.currentTarget.dataset.prompt
    this.resize()
    this.inputTarget.focus()
  }

  update() {
    const empty = this.inputTarget.value.trim() === "" && this.dt.files.length === 0
    this.sendTarget.disabled = empty || this.submitting
  }

  submitStart() {
    this.submitting = true
    this.update()
  }

  submitEnd(event) {
    this.submitting = false
    if (event.detail.success) {
      this.inputTarget.value = ""
      this.dt = new DataTransfer()
      this.filesTarget.value = ""
      this.renderChips()
      this.resize()
    }
    this.update()
  }

  dragEnter(event) {
    if (!event.dataTransfer?.types.includes("Files")) return
    this.dragDepth++
    this.boxTarget.classList.add("is-dragging")
  }

  dragLeave() {
    this.dragDepth = Math.max(0, this.dragDepth - 1)
    if (this.dragDepth === 0) this.boxTarget.classList.remove("is-dragging")
  }

  drop(event) {
    if (!event.dataTransfer?.files.length) return
    event.preventDefault()
    this.dragDepth = 0
    this.boxTarget.classList.remove("is-dragging")
    this.add(Array.from(event.dataTransfer.files))
  }
}
