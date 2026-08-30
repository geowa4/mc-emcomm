# mc_emcomm — Technical Specification

`mc_emcomm` is a single Phoenix LiveView application — OTP app `mc_emcomm` / module `McEmcomm` / Fly app `mc-emcomm` / env prefix `MC_EMCOMM_` — that replaces the Hugo website for Monroe County EmComm (Monroe County, NY ARES/RACES, a 501(c)(3) nonprofit) at monroecountyemcomm.org. This document is authoritative and uses RFC 2119 keywords (MUST, SHOULD, MAY, etc.). No personal names appear anywhere. Supporting sources are listed in Appendix B.

## 1. Overview

`mc_emcomm` is a single web application that runs the online presence and member-management workflow for Monroe County EmComm, the Monroe County, NY ARES/RACES organization (a 501(c)(3) nonprofit). It serves three audiences: the general public, who see an informational website; approved members, who use a private portal for training records, exercises, equipment tracking, and net logging; and administrators, who manage membership and catalogs. It replaces the organization's existing Hugo static website at monroecountyemcomm.org and consolidates manual and spreadsheet-based processes into one system. The application is built with Phoenix LiveView and is hosted on Fly.io.

Concretely, it is a server-rendered Phoenix LiveView app providing:
1. a public marketing/information site;
2. an authenticated member portal;
3. an admin console;
4. an asset inventory with QR-driven "sighting" capture;
5. exercises with multiple named geofenced locations and attendance;
6. a live net logger; and
7. training records (capabilities, courses, certifications).

## 2. Goals / Non-goals

**Goals.** The app MUST replace all current Hugo pages; MUST keep all member PII (call signs, addresses, QTH points) out of public view; MUST run on Fly.io with a Managed Postgres + PostGIS cluster and a private Tigris bucket; and SHOULD minimize third-party dependencies.

**Non-goals.** No paid membership/billing; no public exposure of member locations or contact data; no offline/downloaded map tiles (prohibited by the OSM tile policy); no background job framework (Oban) — periodic work MUST use a supervised OTP task/GenServer with a timer.

## 3. Tiers & permissions matrix

Three tiers exist on a single account: public (anonymous); member (authenticated AND admin-approved, `status = approved`); admin (`is_admin` boolean on the same account).

| Capability / route | public | member | admin |
|---|---|---|---|
| Home / About / Training / Calendar / Donations | Yes | Yes | Yes |
| Resources documents (gated) | No | Yes | Yes |
| Exercises list `/exercises` | Yes (summary) | Yes | Yes |
| Exercises detail incl. locations/attachments `/app/exercises` | No | Yes | Yes |
| Exercises CRUD `/admin/exercises` | No | No | Yes |
| Asset sighting page (image + name + form only) `/a/:public_id/s` | Yes | Yes | Yes |
| Asset inventory detail (log, map, metadata) `/app/inventory/:public_id` | No | Yes | Yes |
| Sighting IP/UA/client-hint/fingerprint columns | No | No | Yes |
| Net console: start / take check-ins | No | Yes (any approved member) | Yes |
| Past nets | No | Yes | Yes |
| Own certifications / courses / capabilities | No | Yes (own) | Yes (all) |
| Catalog CRUD (capabilities, courses, certifications) | No | No | Yes |
| Membership approvals & audit | No | No | Yes |
| Leadership roles editing | No | No | Yes |

Route groups MUST be enforced with distinct `live_session` scopes (`:public`, `:member`, `:admin`), each with an `on_mount` hook. Admin-only columns within a member-visible sighting view MUST be gated in the template AND the query layer, not merely hidden with CSS.

## 4. Membership state machine

States: `pending`, `approved`, `rejected`, `inactive`. Transitions: `pending → approved`; `pending → rejected`; `approved ↔ inactive`; `rejected → pending`. All transitions are admin-only, and each writes a `membership_audit` row (`actor_user_id`, `from_status`, `to_status`, `reason`, `inserted_at`). `reason` MUST be present for `→ rejected` and `→ inactive`; it MAY be null otherwise. New registrations enter `pending`. Only `approved` members pass the `:member` on_mount gate.

## 5. Template usage

The project is bootstrapped from the `geowa4/base-phoenix` template. Template internals are inherited from the template as cloned; reconcile them with this specification during Stage 1 (see Appendix A).
1. `gh repo create <owner>/mc-emcomm --template geowa4/base-phoenix --private --clone`.
2. `mix mc_emcomm.rename --otp mc_emcomm --module McEmcomm` — flags are as defined by the template's rename task.
3. `mix setup`.
4. `mix usage_rules.sync`.
5. `mix precommit`.
6. `mix phx.server`.

The LICENSE copyright line MUST be updated (MIT retained). The README MUST be rewritten for `mc_emcomm`.

## 6. Architecture & contexts

Phoenix 1.8.x; Phoenix LiveView (the 1.1 line shipped mid-2025; the published line is now 1.2.x); OTP 25+ floor; Bandit. Contexts: Accounts (users, auth, `is_admin`); Members (profile, roles, QTH, quadrant, status, membership audit); Capabilities (catalog + `member_capabilities`); Courses (catalog + `member_courses`); Certifications (catalog + `member_certifications`); Assets (inventory, `public_id`, QR); Sightings (rows and lifecycle); Exercises (exercises, locations, attachments, attendance); Net (sessions, check-ins); Content (public pages, resources documents, calendar).

## 7. Data model

All tables carry `id` (bigserial), `inserted_at`, `updated_at` unless noted. All `geography(Point,4326)` columns MUST have a GiST index. Enums are stored as `:string` with `Ecto.Enum`. PostGIS MUST be enabled by the first project migration (`CREATE EXTENSION IF NOT EXISTS postgis`).

### 7.1 `users` (template, extended)

| Column | Type | Constraints |
|---|---|---|
| `email` | citext | unique, not null |
| `hashed_password` | string | nullable (magic-link-only accounts) |
| `confirmed_at` | utc_datetime | nullable |
| `is_admin` | boolean | not null, default `false` |

Template-generated columns/tokens tables are retained unchanged.

### 7.2 `members`

| Column | Type | Constraints |
|---|---|---|
| `user_id` | FK → users | not null, unique |
| `call_sign` | citext | nullable; unique (partial, where not null) |
| `name` | string | not null |
| `qth_address` | text | nullable |
| `qth_point` | geography(Point,4326) | nullable |
| `quadrant` | enum `NE\|NW\|SE\|SW\|out_of_county` | nullable; member-set, never computed |
| `license_class` | enum `technician\|general\|amateur_extra\|advanced\|novice` | nullable |
| `role` | enum `president\|vice_president\|secretary\|treasurer\|emergency_coordinator\|assistant_emergency_coordinator\|director_at_large\|member` | not null, default `member`; admin-editable only |
| `status` | enum `pending\|approved\|rejected\|inactive` | not null, default `pending` |

Indexes: unique `user_id`; unique partial `call_sign`; GiST `qth_point`; btree `status`, `role`.

### 7.3 `membership_audit`

| Column | Type | Constraints |
|---|---|---|
| `member_id` | FK → members | not null |
| `actor_user_id` | FK → users | not null |
| `from_status` | string | not null |
| `to_status` | string | not null |
| `reason` | text | required when `to_status` ∈ {`rejected`, `inactive`}; else nullable |
| `inserted_at` | utc_datetime_usec | not null (no `updated_at`) |

Indexes: `member_id`.

### 7.4 `capabilities` (admin catalog)

| Column | Type | Constraints |
|---|---|---|
| `name` | citext | not null, unique |
| `code` | string | nullable |
| `description` | text | nullable |
| `active` | boolean | not null, default `true` |

### 7.5 `member_capabilities`

| Column | Type | Constraints |
|---|---|---|
| `member_id` | FK → members | not null |
| `capability_id` | FK → capabilities | not null |
| `notes` | text | nullable |

Indexes: unique `(member_id, capability_id)`.

### 7.6 `courses` (admin catalog)

| Column | Type | Constraints |
|---|---|---|
| `name` | citext | not null, unique |
| `code` | string | nullable (e.g. `IS-100`, `AUXCOMM`) |
| `description` | text | nullable |
| `active` | boolean | not null, default `true` |

### 7.7 `member_courses`

| Column | Type | Constraints |
|---|---|---|
| `member_id` | FK → members | not null |
| `course_id` | FK → courses | not null |
| `completed_on` | date | nullable |
| `evidence_key` | string | nullable (Tigris key) |
| `evidence_filename` | string | nullable |
| `evidence_content_type` | string | nullable |
| `verified` | boolean | not null, default `false`; admin-set |

Indexes: unique `(member_id, course_id)`.

### 7.8 `certifications` (admin catalog)

| Column | Type | Constraints |
|---|---|---|
| `name` | citext | not null, unique |
| `code` | string | nullable (e.g. `AUXC`, `COML`, `COMT`) |
| `description` | text | nullable |
| `prerequisite_course_id` | FK → courses | nullable |
| `requires_task_book` | boolean | not null, default `true` |
| `active` | boolean | not null, default `true` |

### 7.9 `member_certifications`

| Column | Type | Constraints |
|---|---|---|
| `member_id` | FK → members | not null |
| `certification_id` | FK → certifications | not null |
| `issued_on` | date | nullable |
| `expires_on` | date | nullable |
| `task_book_key` | string | nullable (completed PTB) |
| `task_book_filename` | string | nullable |
| `task_book_content_type` | string | nullable |
| `certificate_key` | string | nullable (credential) |
| `certificate_filename` | string | nullable |
| `certificate_content_type` | string | nullable |
| `verified` | boolean | not null, default `false`; admin-set |
| `notes` | text | nullable |

Indexes: unique `(member_id, certification_id)`.

### 7.10 `assets`

| Column | Type | Constraints |
|---|---|---|
| `public_id` | char(6) | not null, unique; Crockford base32 |
| `name` | string | not null |
| `description` | text | nullable |
| `image_key` | string | nullable |
| `image_filename` | string | nullable |
| `image_content_type` | string | nullable |
| `active` | boolean | not null, default `true` |

Indexes: unique `public_id`.

### 7.11 `sightings`

Lifecycle fields are grouped by the update point that writes them (§9).

**Identity and visit (update point 0, HTTP mount)**

| Column | Type | Constraints |
|---|---|---|
| `asset_id` | FK → assets | not null |
| `session_token` | string | not null; signed cookie value |
| `visited_at` | utc_datetime_usec | not null |
| `remote_ip` | inet | nullable; from `Fly-Client-IP` |
| `fly_region` | string | nullable |
| `user_agent` | text | nullable |
| `sec_ch_ua` | string | nullable |
| `sec_ch_ua_platform` | string | nullable |
| `sec_ch_ua_mobile` | string | nullable |
| `accept_language` | string | nullable |
| `referer` | text | nullable |
| `browser_name` | string | nullable; parsed |
| `browser_version` | string | nullable; parsed |
| `os_name` | string | nullable; parsed |
| `os_version` | string | nullable; parsed |
| `device_type` | string | nullable; parsed |

**Client environment (update point 1, socket connect)**

| Column | Type | Constraints |
|---|---|---|
| `connected_at` | utc_datetime_usec | nullable |
| `timezone` | string | nullable |
| `screen_w` | integer | nullable |
| `screen_h` | integer | nullable |
| `device_pixel_ratio` | float | nullable |
| `languages` | {array, string} | nullable |
| `connection_type` | string | nullable |
| `touch` | boolean | nullable |

**Geolocation (update point 1, after permission)**

| Column | Type | Constraints |
|---|---|---|
| `located_at` | utc_datetime_usec | nullable |
| `point` | geography(Point,4326) | nullable |
| `accuracy` | float | nullable; meters |
| `altitude` | float | nullable |
| `heading` | float | nullable |
| `speed` | float | nullable |
| `geo_denied` | boolean | not null, default `false` |

**Submission (update point 2, form submit)**

| Column | Type | Constraints |
|---|---|---|
| `submitted_at` | utc_datetime_usec | nullable |
| `call_sign` | citext | nullable |
| `member_id` | FK → members | nullable; auto-linked by call sign or session |
| `claimed_responsibility` | boolean | not null, default `false` |
| `note` | text | nullable |
| `verified` | boolean | not null, default `false` |
| `exercise_id` | FK → exercises | nullable |
| `exercise_location_id` | FK → exercise_locations | nullable |

**Retention**

| Column | Type | Constraints |
|---|---|---|
| `scrubbed_at` | utc_datetime_usec | nullable; set by the retention task |

Indexes: `asset_id`; `member_id`; `exercise_id`; `session_token`; `visited_at`; GiST `point`. Columns in the first three groups are admin-only in every query and view.

### 7.12 `exercises`

| Column | Type | Constraints |
|---|---|---|
| `title` | string | not null |
| `description` | text | nullable |
| `starts_at` | utc_datetime | not null |
| `ends_at` | utc_datetime | not null; check `ends_at > starts_at` |
| `visibility` | enum `public\|members` | not null, default `members` |
| `created_by_id` | FK → users | not null |

Indexes: `starts_at`; `visibility`.

### 7.13 `exercise_locations`

| Column | Type | Constraints |
|---|---|---|
| `exercise_id` | FK → exercises | not null |
| `name` | string | not null; defaults to `"Primary Site"` when the exercise is created with exactly one location |
| `point` | geography(Point,4326) | not null |
| `geofence_radius_m` | integer | not null, default `500` |
| `notes` | text | nullable |
| `position` | integer | not null, default `0` |

Indexes: `exercise_id`; GiST `point`; unique `(exercise_id, name)`.

### 7.14 `exercise_attachments`

| Column | Type | Constraints |
|---|---|---|
| `exercise_id` | FK → exercises | not null |
| `key` | string | not null (Tigris key) |
| `filename` | string | not null |
| `content_type` | string | not null |
| `description` | text | **not null**, non-empty |
| `uploaded_by_id` | FK → users | not null |

Indexes: `exercise_id`.

### 7.15 `exercise_attendance`

| Column | Type | Constraints |
|---|---|---|
| `exercise_id` | FK → exercises | not null |
| `member_id` | FK → members | not null |
| `source` | enum `manual\|asset_checkin\|admin` | not null |
| `sighting_id` | FK → sightings | nullable; set when `source = asset_checkin` |
| `recorded_at` | utc_datetime_usec | not null |

Indexes: unique `(exercise_id, member_id)`.

### 7.16 `net_sessions`

| Column | Type | Constraints |
|---|---|---|
| `started_by_member_id` | FK → members | not null |
| `name` | string | nullable |
| `started_at` | utc_datetime | not null |
| `ended_at` | utc_datetime | nullable |
| `notes` | text | nullable |

Indexes: `started_at`.

### 7.17 `net_checkins`

| Column | Type | Constraints |
|---|---|---|
| `net_session_id` | FK → net_sessions | not null |
| `call_sign` | citext | not null |
| `member_id` | FK → members | nullable; auto-linked by call sign |
| `quadrant` | enum `NE\|NW\|SE\|SW\|out_of_county` | nullable; prefilled from member, overridable by net control |
| `notes` | text | nullable |
| `recorded_at` | utc_datetime_usec | not null |

Indexes: `net_session_id`; `member_id`.

### 7.18 `documents` (Resources)

| Column | Type | Constraints |
|---|---|---|
| `title` | string | not null |
| `key` | string | not null (Tigris key) |
| `filename` | string | not null |
| `content_type` | string | not null |
| `members_only` | boolean | not null, default `true` |
| `active` | boolean | not null, default `true` |
| `position` | integer | not null, default `0` |

## 8. Routes & live_sessions

**`:public`** — `/`, `/about`, `/training`, `/resources` (list; downloads gated), `/calendar`, `/donations`, `/exercises`, `/exercises/:id` (summary), `/a/:public_id/s`.
**`:member`** (approved) — `/app`, `/app/profile`, `/app/exercises`, `/app/exercises/:id`, `/app/inventory`, `/app/inventory/:public_id`, `/app/net`, `/app/net/:id`.
**`:admin`** — `/admin`, `/admin/members`, `/admin/exercises`, `/admin/inventory`, `/admin/capabilities`, `/admin/courses`, `/admin/certifications`, `/admin/documents`.
Template auth routes are retained.

## 9. LiveViews & UX flows

### Sighting-first QR flow (three update points)
The QR SVG (eqrcode) MUST encode a sighting URL, never a plain asset page: `{MC_EMCOMM_QR_BASE_URL}/a/{public_id}/s`. `MC_EMCOMM_QR_BASE_URL` is the canonical public origin (e.g. `https://monroecountyemcomm.org`) with no trailing slash.
**Update point 0 — HTTP mount (server, before socket).** A sighting row MUST be created during the LiveView's HTTP mount (disconnected render), or in a plug before it, so the visit is recorded even if the WebSocket never connects. Captured from the conn: `remote_ip` (read `Fly-Client-IP` first; fall back to the first `X-Forwarded-For` address, then `conn.remote_ip`), `fly_region` (`Fly-Region`), raw `user_agent`, `sec_ch_ua`, `sec_ch_ua_platform`, `sec_ch_ua_mobile`, `accept_language`, `referer`, and a signed `session_token` cookie so later updates bind to the same visitor. `visited_at` is set. UA parsing populates `browser_name`/`version`, `os_name`/`version`, and `device_type` via ua_inspector.
**Update point 1 — socket connect (JS hook pushEvent).** Pushes `timezone` (`Intl.DateTimeFormat().resolvedOptions().timeZone`), `screen_w`/`h`, `device_pixel_ratio`, `languages`, `connection_type` (if `navigator.connection`), and `touch`; the row is UPDATED and `connected_at` is set. The hook then requests Geolocation; on grant it pushes `point`/`accuracy`/`altitude`/`heading`/`speed` and the row is UPDATED with `located_at`; on deny `geo_denied = true`. Geolocation requires an HTTPS secure context, which Fly provides.
**Update point 2 — form submit.** `call_sign`, optional `note`, `claimed_responsibility`. The row is UPDATED with `member_id` (auto-linked if the call sign matches an approved member, or from the logged-in session), `submitted_at`, `verified`, and the geofence-matched `exercise_id`/`exercise_location_id`. If the submitter is an approved member and the sighting matched an active exercise location, an `exercise_attendance` row with `source = asset_checkin` MUST be created, carrying the `sighting_id`.
The public sighting page MUST render ONLY the asset image, the asset name, and the sighting form. Recent sightings, the sighting log, maps, and all metadata are members/admin-only at `/app/inventory/:public_id`; IP/UA/client-hint/fingerprint columns are admin-only.

### Profile
Members edit their own QTH (map-click pin drop), quadrant (help text: quadrants split E/W by the Genesee River and N/S by the Erie Canal, as defined in the organization's net control script), license class, capabilities, courses (evidence upload), and certifications. For each certification the UI SHOULD show whether the member has the prerequisite course on record, and MUST provide two upload slots: completed Position Task Book and credential/certificate. `verified` is admin-set. Role and `is_admin` are not member-editable.

### Admin approval
A queue of pending members with approve/reject; reject requires a reason; every action writes a `membership_audit` row.

### Catalog CRUD
Admin LiveViews for capabilities, courses, and certifications (including `prerequisite_course_id` and `requires_task_book`).

### Exercises with multiple named locations & attachments
Admin CRUD. An exercise holds many `exercise_locations`, each with a name, a map-placed point, and `geofence_radius_m`. Creating an exercise with a single location defaults its name to "Primary Site". The detail map renders every location as a marker plus a radius circle. Attachments upload to Tigris and each MUST have a `description`.

### Net console
Any approved member starts a session and takes live check-ins (call sign auto-links to members; quadrant prefills from the member record and is overridable; notes). Check-ins broadcast over Phoenix PubSub to a live map and roster. Past nets are members-only.

## 10. PostGIS design
PostGIS is used ONLY for storing points and for geofence matching. Matching MUST query `exercise_locations` joined to active exercises (the `starts_at`/`ends_at` window contains the sighting time) using `ST_DWithin(location.point, sighting.point, location.geofence_radius_m)` on geography (meters), ordered by `ST_Distance`, limit 1. All point columns are GiST-indexed. No quadrant is computed geometrically.

## 11. File storage
A private Fly Tigris bucket holds all uploads (asset images, course/certification evidence, exercise attachments, documents). LiveView `allow_upload` MUST use `external:` with a presigned POST form from `ReqS3.presign_form/1`; viewing MUST use short-lived URLs from `ReqS3.presign_url/1`. Tests MUST stub the presign functions. Standard env vars `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_REGION`, `AWS_ENDPOINT_URL_S3` drive ReqS3.

## 12. Maps
Leaflet 1.9.4 is bundled via esbuild with OpenStreetMap tiles; map-click pin drop is used for QTH and exercise-location placement. Leaflet 1.9.4 is the last stable 1.x (2.0 is alpha); pin exactly 1.9.4. The app MUST comply with the OSM Tile Usage Policy: identifying User-Agent, "© OpenStreetMap contributors" attribution, and never bulk-download or offline-cache tiles.

## 13. Geocoding
Nominatim is OPTIONAL (map-click is primary). If enabled, the app MUST comply with the OSMF Nominatim Usage Policy: "absolute maximum of 1 request per second"; "Provide a valid HTTP Referer or User-Agent identifying the application (stock User-Agents as set by http libraries will not do)"; "Results must be cached on your side"; auto-complete and systematic queries are forbidden; "Clearly display attribution as suitable for your medium." Therefore geocode server-side, rate-limit to ≤1 req/s, cache results, send an identifying User-Agent, and never geocode per keystroke.

## 14. Net logger
See §9. Sessions and check-ins persist; PubSub drives the live map and roster; past nets are members-only.

## 15. Public pages
Home, About (renders leadership from `role != member` as role + name + call sign), Training, Resources (documents list; downloads gated), Calendar, Donations. The primary repeater and net details MUST be shown only after leadership confirmation. Current listings: the Monroe County RACES primary is 146.610 MHz (−0.6 offset), PL 110.9, callsign W2ARM, Rochester NY (Cobbs Hill), FM/P-25; the organization's groups.io page still lists N2MPE for 146.61, so the W2ARM (ex-N2MPE) transition MUST be confirmed with leadership, along with the exact weekly net day/time (Thursday 19:00 per RepeaterBook; general meeting on the fourth Thursday monthly except Jul/Aug/Dec).

## 16. Deployment
Fly app `mc-emcomm`; env prefix `MC_EMCOMM_`.
**Database.** Fly Managed Postgres; PostGIS MUST be enabled at creation. The MPG default major version is PG16, so PG17 MUST be requested explicitly: `fly mpg create --pg-major-version 17 --enable-postgis-support`. Attach with `fly mpg attach <clusterID> -a mc-emcomm` (pooled `DATABASE_URL` via PgBouncer).
**Object storage.** Private Tigris bucket (`fly storage create`); AWS-style secrets set as Fly secrets.
**Env vars.** `MC_EMCOMM_QR_BASE_URL`, `MC_EMCOMM_SIGHTING_RAW_RETENTION_DAYS`, `MC_EMCOMM_NOMINATIM_USER_AGENT`, `MC_EMCOMM_MAP_TILE_URL`, plus `DATABASE_URL`, `SECRET_KEY_BASE`, `PHX_HOST`, the `AWS_*`/Tigris set, and the Resend key.
The `fly.toml` health-check paths/ports, `release_command`, blue-green, and `min_machines_running` settings are inherited from the template; reconcile them with this specification during Stage 1. If MPG PG17+PostGIS is unavailable in the target region, fall back to PG16.

## 17. CI
CI MUST run against `postgis/postgis:17-3.5`. The pipeline SHOULD mirror precommit (format check, compile warnings-as-errors, Credo, Dialyzer, `mix test`). Job definitions are inherited from the template's `.github/workflows`, reconciled with this specification during Stage 1, and extended with the PostGIS service.

## 18. Testing
Geofence/PostGIS tests MUST run against real PostGIS (CI service + a local PostGIS dev DB), not a mock. `ReqS3.presign_form/1` and `presign_url/1` MUST be stubbed. Sighting-flow tests MUST cover the disconnected HTTP-mount insert, the connect update, geolocation grant/deny, and the submit update — including creation of the `exercise_attendance` row (with its `sighting_id`) for approved members. Membership state machine: table-driven tests for every legal/illegal transition with audit assertions. Permissions: each `live_session` gate and each admin-only sighting column MUST have an authorization test.

## 19. Seeds
Idempotent seeds create: an admin account; a handful of members across roles and quadrants; a capabilities catalog (2m/70cm HT field-programmable, APRS, HF voice); a courses catalog including AUXCOMM, IS-100, IS-200, IS-700, IS-800; a certifications catalog seeded with AUXC (`prerequisite_course_id → AUXCOMM`, `requires_task_book = true`), COML, and COMT; one exercise with a single location (auto-named "Primary Site") and one multi-location exercise; and sample assets with generated `public_id`s.

## 20. Privacy, retention & deletion
Member PII MUST never render on public routes. Sighting IP/UA/client-hint/geolocation data is visible ONLY to admins and MUST be excluded from member-facing queries. Raw sighting telemetry is retained for `MC_EMCOMM_SIGHTING_RAW_RETENTION_DAYS`, after which a supervised periodic OTP task (a GenServer/Task on a timer — NO Oban) MUST scrub the raw columns (IP, UA, client hints, precise point) and set `scrubbed_at`, retaining anonymized/aggregate fields. Member deletion MUST cascade sensibly: audit rows retain actor references; `member_certifications`/`member_courses`/`member_capabilities` are removed and their Tigris objects purged; sightings are de-linked from `member_id`; `net_checkins` keep the `call_sign` text with the member link nulled.

## 21. Staged build plan (no time estimates)
1. **Foundation** — clone the template, rename, reconcile pins, auth, `is_admin`, base layout, public pages. Benchmark: `mix precommit` green, public site renders, auth works.
2. **Members & membership** — member schema, profile LiveView, state machine + audit, admin approval queue, About leadership rendering. Benchmark: the full transition test matrix passes; leadership renders from roles.
3. **Catalogs** — capabilities, courses, certifications + admin CRUD; profile records with evidence; prerequisite display. Benchmark: seeds load AUXC/COML/COMT; a member can attach a PTB and certificate.
4. **Storage & maps** — Tigris presign upload/view (stubbed in tests), Leaflet pin drop. Benchmark: uploads round-trip; QTH pin persists.
5. **Assets & sightings** — `public_id`, QR to `/a/:public_id/s`, sighting-first flow with three update points, admin-only metadata, member inventory detail. Benchmark: disconnected mount creates the row; connect/geo/submit updates land; attendance is created for approved members.
6. **Exercises & geofence** — exercises, multiple named locations (Primary Site default), attachments with required `description`, attendance, `ST_DWithin` matching, map circles. Benchmark: in-radius/in-window matches; outside/expired does not.
7. **Net logger** — sessions, live check-ins, PubSub map, past nets. Benchmark: two browsers see live check-ins; quadrant prefill/override works.
8. **Hardening** — retention scrub task, privacy/deletion, CI PostGIS parity, deploy to Fly with MPG PG17+PostGIS and Tigris. Benchmark: the retention task scrubs past-cutoff rows; the production deploy is healthy; migrations run via the release command.

**Thresholds.** If the template already provides a remote-IP plug, use it. If ua_inspector's DB download is heavy in CI/build, store raw UA headers only and parse lazily on display. If MPG PG17+PostGIS is unavailable in the target region, fall back to PG16.

## 22. Open questions / future work
Confirm with leadership: the W2ARM (ex-N2MPE) callsign transition, the exact weekly net day/time, and the repeater PL/offset. Future work: ICS-form generation from net logs; exercise after-action report export; optional self-hosted Nominatim; a static quadrant map overlay; FCC ULS call-sign lookup.

## Appendix A — Template baseline

The project is cloned from the `geowa4/base-phoenix` template, which provides: Elixir 1.20 / OTP 28; Bandit as the web server; Ecto + PostgreSQL 17; `phx.gen.auth` with magic-link and password authentication using Argon2id; Resend/Swoosh for outbound email plus a signature-verified inbound webhook that feeds an authenticated `/inbox` LiveView over PubSub; health endpoints; Prometheus metrics on a private port; OpenTelemetry; JSON logs; a five-layer `mix precommit` quality gate; Dialyzer in CI; Fly.io blue-green deployment with a release migrator; `AGENTS.md` / `CLAUDE.md` / `GEMINI.md`, `usage_rules` sync, and Tidewave MCP in development; `mise.toml`; a rename task `mix mc_emcomm.rename --otp <otp> --module <Module>` that runs once and then deletes itself; and a default branch of `trunk`.

Template-managed dependency pins, the `precommit` alias steps, `config/runtime.exs` variable names, `fly.toml` health-check/release/blue-green settings, and CI workflow definitions are inherited from the template as cloned and govern wherever this specification is silent.

## Appendix B — Verified versions & sources
**Certifications.** CISA "Communications Unit Training Resources" and "Communications Unit" pages (COML/COMT/AUXCOMM curriculum, courses + Position Task Books; national standards for qualification, certification, credentialing); CISA AUXCOMM PTB PDF (NQS competencies, evaluators initial tasks); NYS DHSES COMU program (COML, COMT, AUXCOMM credentialed positions).
**Platform.** Fly request-headers doc (`Fly-Client-IP`, `X-Forwarded-For`); Fly `fly mpg create` (`--pg-major-version` "Supported versions are 16 and 17. (default 16)"; `--enable-postgis-support`); Fly MPG extensions page ("Currently only Vector and PostGIS are supported"); Fly community PG17 MPG announcement; ReqS3 hexdocs/GitHub (`presign_form/1`, `presign_url/1`, `AWS_*` env vars, `allow_upload` external example); eqrcode hexdocs (no other dependencies; `EQRCode.encode |> EQRCode.svg`; 0.2.x); ua_inspector GitHub/hex (actively maintained, v3.12.0, DB via `mix ua_inspector.download`); Phoenix/LiveView hex versions (Phoenix 1.8.0 released Aug 5 2025 requiring OTP 25+; current 1.8.x; LiveView published line 1.2.x); Leaflet 1.9.4 (released 18 May 2023, BSD-2-Clause, 2.0 alpha); gh `repo create` manual (`--template`, `--private`, `--clone`); `postgis/postgis:17-3.5` Docker Hub tag.
**Web platform.** MDN Geolocation API / GeolocationCoordinates (secure context; latitude, longitude, altitude, accuracy, altitudeAccuracy, heading, speed); MDN User-Agent Client Hints (Sec-CH-UA, Sec-CH-UA-Mobile, Sec-CH-UA-Platform low-entropy; platform values; high-entropy via Accept-CH; Safari/Firefox do not implement — keep the raw UA fallback).
**Geocoding & tiles.** OSMF Nominatim Usage Policy and Tile Usage Policy (quotes as above).
**Organization.** MonroeCountyEmcomm groups.io (501(c)(3); N2MPE 146.61 (−) / 444.45 (+); fourth-Thursday meetings except Jul/Aug/Dec); RARA repeater listing rochesterham.org (146.610/146.010 110.9 W2ARM Cobbs Hill FM, P-25, Monroe County RACES Primary); RepeaterBook ID 36-7183 (Thu 19:00 net); RadioReference Wiki Monroe County (NY) (146.610 N2MPE PL 110.9); monroecountyemcomm.org Home/About/Resources.