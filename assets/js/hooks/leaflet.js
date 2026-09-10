import L from "../../vendor/leaflet/leaflet.js"

// Leaflet guesses where its marker images live by reading the background-image
// of `.leaflet-default-icon-path` from leaflet.css and requires that URL to end
// in exactly `marker-icon.png`. In production `mix phx.digest` rewrites it to
// `marker-icon-<hash>.png?vsn=d`, the guess fails, and every marker renders as
// a broken image. Pin the (undigested, still served) path so no guessing runs.
L.Icon.Default.imagePath = "/images/leaflet/"

export default L
