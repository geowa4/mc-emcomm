# mc_emcomm

The website and member portal for **Monroe County EmComm**, the volunteer
amateur-radio emergency communications group (ARES/RACES) serving Monroe
County, New York. It is live at
[monroecountyemcomm.org](https://monroecountyemcomm.org).

When phones, internet, and power fail, licensed radio operators keep
hospitals, shelters, and emergency managers talking. This application is how
the group organizes that work: who is trained for what, what equipment is
where, and who showed up when it counted. It replaced a static website and a
handful of spreadsheets with one Phoenix LiveView app.

## What it does

- **For the public** — who the group is, how to get trained, resources,
  the calendar, donations, and the schedule of upcoming operations.
- **For members** — a private portal with a profile (location, quadrant,
  capabilities, courses, certifications), operation details with locations,
  attachments, and attendance, the equipment inventory, and a live net
  logger for running on-air check-ins.
- **For admins** — membership approval and audit, the training and
  capability catalogs, operations and equipment management, and document
  uploads.

### Equipment sightings by QR code

Every tracked asset, from a go-kit radio to the repeater trailer, carries a
QR code. Scanning it opens a public page that records the sighting, then
asks the visitor for permission to share their location and finally their
call sign. A sighting from a member inside an active operation's geofence
counts as attendance automatically, so nobody has to keep a paper sign-in
sheet in the field.

## Privacy

Member personal information (call signs, addresses, home locations) is never
shown on public pages. Raw sighting telemetry (IP address, browser details,
geolocation) is visible to admins only and is scrubbed automatically after a
retention period.

## Built with

- Elixir and Phoenix LiveView on PostgreSQL with PostGIS for geofencing
- Leaflet and OpenStreetMap tiles for maps
- Resend for email, Fly Tigris for file storage
- Deployed blue-green on Fly.io

## Documentation

- [`mcemcomm-app.md`](mcemcomm-app.md) — the technical specification this
  application implements.
- [`CONTRIBUTING.md`](CONTRIBUTING.md) — local setup, testing, database
  changes, configuration, and everything else a contributor needs.
- [`DEPLOY.md`](DEPLOY.md) — the operator reference: first deploy, custom
  domain, continuous deployment, and the runbook.
- [`AGENTS.md`](AGENTS.md) — conventions for coding agents and humans working
  in this repository.

## License

[MIT](LICENSE).
