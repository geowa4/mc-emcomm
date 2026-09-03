// Mirrors the document's current theme choice onto the toggle's buttons as
// aria-pressed. The choice lives in localStorage and on <html> (see the inline
// script in root.html.heex), so only the client can report it.
const ThemeToggle = {
  mounted() {
    this.sync = () => {
      const root = document.documentElement
      const current =
        root.getAttribute("data-theme-source") === "system"
          ? "system"
          : root.getAttribute("data-theme")

      this.el.querySelectorAll("[data-phx-theme]").forEach(button => {
        button.setAttribute("aria-pressed", String(button.dataset.phxTheme === current))
      })
    }

    window.addEventListener("phx:set-theme", this.sync)
    window.addEventListener("storage", this.sync)
    this.sync()
  },

  updated() {
    this.sync()
  },

  destroyed() {
    window.removeEventListener("phx:set-theme", this.sync)
    window.removeEventListener("storage", this.sync)
  },
}

export default ThemeToggle
