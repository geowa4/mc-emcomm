import L from "../../vendor/leaflet/leaflet.js"

// Read-only map: renders every marker in data-markers (JSON array of
// {lat, lng, title, radius_m}) plus a geofence-radius circle when
// radius_m is given (operation locations, §9 "Operations"). Used for operation
// detail, inventory sighting maps, and the net console's live roster map.
const LeafletMap = {
  mounted() {
    this.map = L.map(this.el)

    L.tileLayer(this.el.dataset.tileUrl || "https://tile.openstreetmap.org/{z}/{x}/{y}.png", {
      maxZoom: 19,
      attribution: "&copy; OpenStreetMap contributors",
    }).addTo(this.map)

    this.layerGroup = L.layerGroup().addTo(this.map)
    this.render()
  },

  updated() {
    this.render()
  },

  render() {
    this.layerGroup.clearLayers()
    const markers = JSON.parse(this.el.dataset.markers || "[]")

    if (markers.length === 0) {
      this.map.setView([43.1566, -77.6088], 10)
      return
    }

    const bounds = []

    markers.forEach(m => {
      const latlng = [m.lat, m.lng]
      bounds.push(latlng)

      const marker = L.marker(latlng)
      if (m.title) marker.bindPopup(m.title)
      marker.addTo(this.layerGroup)

      if (m.radius_m) {
        L.circle(latlng, {radius: m.radius_m, color: "#FD4F00", fillOpacity: 0.08}).addTo(
          this.layerGroup,
        )
      }
    })

    if (bounds.length === 1) {
      this.map.setView(bounds[0], 15)
    } else {
      this.map.fitBounds(bounds, {padding: [24, 24]})
    }
  },

  destroyed() {
    this.map && this.map.remove()
  },
}

export default LeafletMap
