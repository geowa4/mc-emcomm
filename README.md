# mc_emcomm

The online presence and member-management system for **Monroe County EmComm**
(Monroe County, NY ARES/RACES, a 501(c)(3) nonprofit) at
monroecountyemcomm.org. A single Phoenix LiveView application replacing the
organization's previous Hugo static site and several spreadsheet-based
processes.

It serves three audiences on one account model:

- **Public** — an informational site: About, Training, Resources, Calendar,
  Donations, and a public exercise schedule.
- **Members** (authenticated, admin-approved) — a private portal: profile
  (QTH, quadrant, capabilities, courses, certifications), exercise detail
  with locations/attachments/attendance, asset inventory detail, and a live
  net logger.
- **Admins** — membership approval and audit, catalog CRUD (capabilities /
  courses / certifications), exercise and asset/QR management, and Resources
  document uploads.

It also runs a QR-code "asset sighting" flow: each tracked asset (radio kit,
repeater trailer, etc.) gets a QR code encoding a public sighting page;
scanning it records a visit, then (with permission) the visitor's client
environment and location, and finally their submitted call sign — auto-
linking to a member record and, inside an active exercise's geofence,
recording attendance.

See `mcemcomm-app.md` in the repository root for the full technical
specification this application implements.

## Stack

- Elixir 1.20 / OTP 28, Phoenix 1.8, LiveView 1.2, Bandit
- Ecto + PostgreSQL 17 with PostGIS (geography columns, `ST_DWithin` geofence
  matching)
- Leaflet 1.9.4 (vendored, no Node/npm) for map-click pin drop and read-only
  markers/geofence circles, tiled from OpenStreetMap
- A private Fly Tigris (S3-compatible) bucket for uploads, via `ReqS3`
  presigned forms/URLs
- `eqrcode` for QR generation, `ua_inspector` for lazy user-agent parsing
- Resend outbound email (Swoosh) and a signature-verified inbound webhook
  feeding an authenticated `/inbox` LiveView over PubSub
- Health endpoints, Prometheus on a private port, OpenTelemetry, JSON logs
- A five-layer quality gate under `mix precommit`; Dialyzer in CI
- Fly.io blue-green deployment with a release migrator (not yet provisioned
  for this project — see Deployment below)

Built from the [`geowa4/base-phoenix`](https://github.com/geowa4/base-phoenix)
template; see `AGENTS.md` for the conventions coding agents (and humans)
should follow in this repository.

## Local setup

You need a PostGIS-enabled Postgres, not plain Postgres — this project
stores `geography(Point,4326)` columns and geofence-matches with
`ST_DWithin`/`ST_Distance`. On Apple Silicon, the official
`postgis/postgis` image has no arm64 build; `imresamu/postgis` is a
multi-arch mirror of the same Postgres 17 + PostGIS 3.5 combination CI uses:

    docker run -d --name mc-emcomm-pg \
      -e POSTGRES_PASSWORD=postgres -p 5433:5432 imresamu/postgis:17-3.5

Config reads the port from `PGPORT` (default `5432`, matching CI's
`postgis/postgis:17-3.5` service container); export it once per shell if
your local Postgres isn't on the default port:

    export PGPORT=5433
    mix setup            # deps, db create+migrate+seed, assets
    mix usage_rules.sync # refreshes AGENTS.md's managed section
    mix precommit
    mix phx.server

`mix run priv/repo/seeds.exs` (idempotent — safe to re-run) creates an admin
account, members across roles/quadrants, the capabilities/courses/
certifications catalogs, two exercises (single- and multi-location), and a
few sample assets. The seed output prints the admin login.

Uploads need a Tigris/S3-compatible bucket to actually round-trip; without
`AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` / `AWS_ENDPOINT_URL_S3` /
`BUCKET_NAME` set, presigning raises — fine for browsing everything else,
just skip file uploads locally until those are set. Tests never touch real
storage: `McEmcomm.Storage` dispatches to `McEmcomm.StorageMock` in test
(`config/test.exs`), so `ReqS3` is never called.

## Environment variables

| Variable | Purpose | Default |
|---|---|---|
| `MC_EMCOMM_QR_BASE_URL` | Canonical public origin encoded into sighting QR codes | `http://localhost:4000` |
| `MC_EMCOMM_SIGHTING_RAW_RETENTION_DAYS` | Days of raw sighting telemetry kept before the retention task scrubs it | `90` |
| `MC_EMCOMM_NOMINATIM_USER_AGENT` | Identifying UA if geocoding is ever enabled (unused today — map-click is primary) | dev placeholder |
| `MC_EMCOMM_MAP_TILE_URL` | Leaflet OSM tile URL template | `https://tile.openstreetmap.org/{z}/{x}/{y}.png` |
| `BUCKET_NAME`, `AWS_*` | Tigris/S3 bucket + credentials (`ReqS3`) | — |
| `PGPORT` | Local/CI Postgres port | `5432` |

Standard template variables (`DATABASE_URL`, `SECRET_KEY_BASE`, `PHX_HOST`,
`RESEND_API_KEY`, `RESEND_WEBHOOK_SECRET`, `MAIL_FROM`, …) are unchanged —
see `config/runtime.exs`.

## Deployment

Not yet provisioned. Per the spec: a Fly Managed Postgres cluster created
with PostGIS enabled (`fly mpg create --pg-major-version 17
--enable-postgis-support`, falling back to PG16 if PG17+PostGIS isn't
available in the target region) and a private Tigris bucket (`fly storage
create`). `fly.toml`, the release migrator, and blue-green settings are
inherited from the template. See `CONTRIBUTING.md` for the general Fly.io
deployment flow this project follows once provisioned.

## Privacy & retention

Member PII (call signs, addresses, QTH points) never renders on public
routes. Sighting IP/user-agent/client-hint/geolocation columns are
admin-only, gated at the query layer as well as the template. A supervised
`McEmcomm.RetentionScrubber` GenServer (no Oban — see the spec's non-goals)
periodically nulls raw sighting telemetry older than
`MC_EMCOMM_SIGHTING_RAW_RETENTION_DAYS`.
