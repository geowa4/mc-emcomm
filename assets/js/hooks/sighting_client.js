// Update point 1 (spec §9): on socket connect, push client environment, then
// request Geolocation and push the grant/deny result. Runs once per mount.
const SightingClient = {
  mounted() {
    this.pushEvent("client_env", {
      timezone: Intl.DateTimeFormat().resolvedOptions().timeZone,
      screen_w: window.screen.width,
      screen_h: window.screen.height,
      device_pixel_ratio: window.devicePixelRatio,
      languages: navigator.languages ? Array.from(navigator.languages) : [navigator.language],
      connection_type: navigator.connection ? navigator.connection.effectiveType : null,
      touch: "ontouchstart" in window || navigator.maxTouchPoints > 0,
    })

    if (!navigator.geolocation) {
      this.pushEvent("geolocation_denied", {})
      return
    }

    navigator.geolocation.getCurrentPosition(
      position => {
        const c = position.coords
        this.pushEvent("geolocation", {
          lat: c.latitude,
          lng: c.longitude,
          accuracy: c.accuracy,
          altitude: c.altitude,
          heading: c.heading,
          speed: c.speed,
        })
      },
      () => this.pushEvent("geolocation_denied", {}),
      {enableHighAccuracy: true, timeout: 10000},
    )
  },
}

export default SightingClient
