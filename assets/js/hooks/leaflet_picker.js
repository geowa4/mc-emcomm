import L from "../../vendor/leaflet/leaflet.js"

// Map-click pin drop used for QTH and operation-location placement (spec §12).
// Renders a single draggable marker; every placement/drag pushes
// `point_selected` with {lat, lng} to the LiveView. The LiveView can also move
// the pin with a `picker:set_point` event, which is how coordinates typed into
// the accompanying form (the keyboard alternative to clicking) reach the map.
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

    this.marker = null
    if (hasInitial) this.placeMarker(L.latLng(center))

    this.map.on("click", e => {
      this.placeMarker(e.latlng)
      this.pushPoint(e.latlng)
    })

    this.handleEvent("picker:set_point", ({id, lat, lng}) => {
      if (id && id !== this.el.id) return
      const latlng = L.latLng(lat, lng)
      this.placeMarker(latlng)
      this.map.setView(latlng, Math.max(this.map.getZoom(), 13))
    })
  },

  placeMarker(latlng) {
    if (this.marker) {
      this.marker.setLatLng(latlng)
      return
    }

    this.marker = L.marker(latlng, {draggable: true, alt: "Selected location"}).addTo(this.map)
    this.marker.on("dragend", () => this.pushPoint(this.marker.getLatLng()))
  },

  pushPoint(latlng) {
    this.pushEventTo(this.el, "point_selected", {lat: latlng.lat, lng: latlng.lng})
  },

  destroyed() {
    this.map && this.map.remove()
  },
}

export default LeafletPicker
