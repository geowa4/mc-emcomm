import L from "../../vendor/leaflet/leaflet.js"

// Map-click pin drop used for QTH and exercise-location placement (spec §12).
// Renders a single draggable marker; every placement/drag pushes
// `point_selected` with {lat, lng} to the LiveView.
const LeafletPicker = {
  mounted() {
    const lat = parseFloat(this.el.dataset.lat)
    const lng = parseFloat(this.el.dataset.lng)
    const hasInitial = !Number.isNaN(lat) && !Number.isNaN(lng)
    const center = hasInitial ? [lat, lng] : [43.1566, -77.6088] // Monroe County, NY

    this.map = L.map(this.el).setView(center, hasInitial ? 13 : 10)

    L.tileLayer(this.el.dataset.tileUrl || "https://tile.openstreetmap.org/{z}/{x}/{y}.png", {
      maxZoom: 19,
      attribution: "&copy; OpenStreetMap contributors",
    }).addTo(this.map)

    this.marker = hasInitial ? L.marker(center, {draggable: true}).addTo(this.map) : null

    if (this.marker) {
      this.marker.on("dragend", () => this.pushPoint(this.marker.getLatLng()))
    }

    this.map.on("click", e => {
      if (this.marker) {
        this.marker.setLatLng(e.latlng)
      } else {
        this.marker = L.marker(e.latlng, {draggable: true}).addTo(this.map)
        this.marker.on("dragend", () => this.pushPoint(this.marker.getLatLng()))
      }
      this.pushPoint(e.latlng)
    })
  },

  pushPoint(latlng) {
    this.pushEventTo(this.el, "point_selected", {lat: latlng.lat, lng: latlng.lng})
  },

  destroyed() {
    this.map && this.map.remove()
  },
}

export default LeafletPicker
