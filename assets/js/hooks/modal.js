// Opens a <dialog> as a true modal so the browser traps focus inside it and
// closes it on Escape. Closing for any reason pushes the LiveView event named
// in data-on-close, which is expected to stop rendering the dialog; when the
// element then leaves the page, focus goes back to whatever opened it.
const Modal = {
  mounted() {
    this.opener = document.activeElement
    this.pushed = false

    // Escape fires `cancel` synchronously and `close` in a later task; either
    // one is enough, and the guard keeps the server from hearing it twice.
    const notify = () => {
      if (this.pushed) return
      this.pushed = true
      this.pushEvent(this.el.dataset.onClose, {})
    }
    this.el.addEventListener("cancel", notify)
    this.el.addEventListener("close", notify)

    if (typeof this.el.showModal === "function" && !this.el.open) {
      this.el.showModal()
    } else {
      this.el.setAttribute("open", "")
    }
  },

  updated() {
    // The server re-rendered the dialog instead of removing it (a validation
    // error, say), so a later close must be reported again.
    this.pushed = false
  },

  destroyed() {
    this.pushed = true
    const opener = this.opener
    if (opener && opener.isConnected && typeof opener.focus === "function") {
      opener.focus()
    }
  },
}

export default Modal
