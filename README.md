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
- Health endpoints, Prometheus on a private port, OpenTelemetry, JSON logs
- A five-layer quality gate under `mix precommit`; Dialyzer in CI
- Fly.io blue-green deployment with a release migrator (not yet provisioned
  for this project — see Deployment below)

Built from the [`geowa4/base-phoenix`](https://github.com/geowa4/base-phoenix)
template; see `AGENTS.md` for the conventions coding agents (and humans)
should follow in this repository.

## Local setup

After a one-time `mix setup` (deps, database, assets), one command brings up
everything — the containers below, create/migrate/seed, the `ua_inspector`
databases, and the server with the S3Mock storage environment defaulted so
uploads round-trip:

    mix dev.server

The rest of this section describes what that runs and how to do each piece
by hand.

You need a PostGIS-enabled Postgres, not plain Postgres — this project
stores `geography(Point,4326)` columns and geofence-matches with
`ST_DWithin`/`ST_Distance`. The official `postgis/postgis` image has no
arm64 build, so on Apple Silicon pin the platform and let it run under
emulation. `mix podman.up` runs this container and the S3Mock one below
(and `mix podman.down` removes them both, deleting the data); by hand:

    podman run -d --name mc-emcomm-pg --platform linux/amd64 \
      -e POSTGRES_PASSWORD=postgres -p 5432:5432 \
      -v mc-emcomm-pgdata:/var/lib/postgresql/data postgis/postgis:17-3.6-alpine

Config defaults to `localhost:5432` (CI runs the same Postgres 17 major via
its `postgis/postgis:17-3.5` service container). If 5432 is taken — say, by
a host-installed Postgres — publish the container on another port and export
`PGPORT` to match, once per shell:

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
`BUCKET_NAME` set, presigning raises — fine for browsing everything else.
For local uploads, [S3Mock](https://github.com/adobe/S3Mock) covers all
three operations the app performs (presigned POST form, presigned GET,
presigned DELETE) with path-style URLs (also started by `mix podman.up`):

    podman run -d --name mc-emcomm-s3 -p 9090:9090 \
      -e COM_ADOBE_TESTING_S3MOCK_STORE_INITIAL_BUCKETS=mc-emcomm-dev \
      -t adobe/s3mock

    AWS_ACCESS_KEY_ID=test AWS_SECRET_ACCESS_KEY=test AWS_REGION=us-east-1 \
      AWS_ENDPOINT_URL_S3=http://localhost:9090 BUCKET_NAME=mc-emcomm-dev \
      mix phx.server

Two things S3Mock does not do: validate signatures (any credentials pass),
or enforce POST policy conditions — an upload over the presign's
`content-length-range` cap is accepted where Tigris rejects it with 400.
Storage lives in the container's tmpdir and is wiped when it stops. Tests
never touch real storage: `McEmcomm.Storage` dispatches to
`McEmcomm.StorageMock` in test (`config/test.exs`), so `ReqS3` is never
called.

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
