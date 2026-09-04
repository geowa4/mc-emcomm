# mc_emcomm — Technical Specification

`mc_emcomm` is a single Phoenix LiveView application — OTP app `mc_emcomm` / module `McEmcomm` / Fly app `mc-emcomm` / env prefix `MC_EMCOMM_` — that replaced the Hugo website for Monroe County EmComm (Monroe County, NY ARES/RACES, a 501(c)(3) nonprofit, branded on the site as "Monroe County ARES/RACES") at monroecountyemcomm.org. This document is authoritative and uses RFC 2119 keywords (MUST, SHOULD, MAY, etc.). No personal names appear anywhere; seed data uses fictional analogues.

This revision describes the application **as built** (repository state at 2026-09-04, 67 commits). The staged build plan of the original specification is complete; §21 records it and the changes that followed. Code comments and tests cite this document by section number (§3, §7.11, §8–§14, §16–§21), so §1–§22 keep their original numbers and new material is added in §23–§27 and the appendices. Supporting sources are listed in Appendix B; the DOM ids, client events, and PubSub messages the test suite treats as a contract are listed in Appendix C.

Where this specification is silent, CONTRIBUTING.md (contributor reference), DEPLOY.md (operator reference), and AGENTS.md (conventions for humans and coding agents) govern; they are cited by section rather than duplicated.

## 1. Overview

`mc_emcomm` runs the online presence and member-management workflow for Monroe County EmComm. It serves three audiences: the general public, who see an informational website; approved members, who use a private portal for training records, operations, equipment tracking, and net logging; and administrators, who manage membership, leadership positions, and catalogs. It consolidated a static website and spreadsheet-based processes into one system, built with Phoenix LiveView and hosted on Fly.io.

Concretely, it is a server-rendered Phoenix LiveView app providing:
1. a public marketing/information site with search and link-preview metadata;
2. an authenticated member portal;
3. an admin console;
4. an asset inventory with QR-driven "sighting" capture;
5. operations with multiple named geofenced locations, attachments, and attendance;
6. a live net logger with location-aware check-ins, a net control role, and automatic check-ins from APRS position reports;
7. training records (capabilities, courses, certifications) with evidence uploads;
8. relational leadership positions that feed the public About page and may grant admin access or new-member notifications;
9. magic-link and password login with optional TOTP two-factor authentication; and
10. an interface that is usable with a keyboard and screen reader on desktop and mobile (§23).

## 2. Goals / Non-goals

**Goals.** The app MUST replace all former Hugo pages at content parity; MUST keep all member PII (call signs, addresses, QTH points, emergency contacts) out of public view; MUST run on Fly.io with a Managed Postgres + PostGIS cluster and a private Tigris bucket; MUST be operable without a pointer and with a screen reader (§23); MUST be usable on a phone (§25); SHOULD minimize third-party dependencies; and SHOULD be discoverable by search engines on its public pages while keeping the sighting page out of every index (§26).

**Non-goals.** No paid membership/billing; no public exposure of member locations or contact data; no offline/downloaded map tiles (prohibited by the OSM tile policy); no background job framework (Oban) — periodic work MUST use a supervised OTP task/GenServer with a timer; no Node.js toolchain (esbuild and Tailwind run from Hex packages, Leaflet is vendored); no LiveView long-polling transport (§24); no OAuth/OIDC (documented as a possible add-on in CONTRIBUTING.md § Add-ons, not installed); no computed quadrants — member location is a point, and county rally points are an admin catalog (§7.21).

## 3. Tiers & permissions matrix

Three tiers exist on a single account: public (anonymous); member (authenticated AND admin-approved, `members.status = approved`); admin. Admin is derived from **two independent sources**, combined in `McEmcomm.Accounts.Scope.admin?/1`: the `users.is_admin` flag (set only by `Accounts.promote_to_admin/1` / `McEmcomm.Release.promote_admin/1`, never castable), OR being an approved member holding a leadership position with `grants_admin = true` (§7.19). Position-derived admin follows the position: it appears on assignment and disappears when the position is vacated, reassigned, or the holder leaves approved status. An admin need not have a member profile at all.

| Capability / route | public | member | admin |
|---|---|---|---|
| Home / About / Training / Calendar / Donations | Yes | Yes | Yes |
| Resources: public documents | Yes | Yes | Yes |
| Resources: members-only documents (titles and downloads) | No | Yes | Yes |
| Operations list `/operations` and detail `/operations/:id` | Yes (public-visibility only) | Yes | Yes |
| Operations portal incl. locations, attachments, attendance `/app/operations` | No | Yes | Yes |
| Mark own attendance on an operation | No | Yes | Yes |
| Operations CRUD `/admin/operations` | No | No | Yes |
| Asset sighting page (image + name + form only) `/a/:public_id/s` | Yes | Yes | Yes |
| Asset inventory list and detail (submitted sightings) `/app/inventory` | No | Yes | Yes |
| Sighting log with IP/UA/client-hint/geolocation columns, sighting map | No | No | Yes |
| Asset CRUD, QR codes `/admin/inventory` | No | No | Yes |
| Net console: start a net, take check-ins, edit check-ins, end a net | No | Yes (any approved member) | Yes |
| Net control role: take / vacate / assign | No | Yes | Yes |
| Past nets | No | Yes | Yes |
| Own profile, capabilities, courses, certifications, emergency contact | No | Yes (own) | Yes (own) |
| Catalog CRUD (capabilities, courses, certifications, default locations, documents) | No | No | Yes |
| Membership approvals & audit; view emergency contacts | No | No | Yes |
| Leadership positions: catalog, holders, order | No | No | Yes |
| Account settings, password, email change, two-factor enrollment | Own (any authenticated user, sudo mode) | Own | Own |
| LiveDashboard `/dev/dashboard` | No | No | Yes (every environment) |
| Health endpoints, robots.txt, sitemap.xml | Yes | Yes | Yes |

Route groups MUST be enforced with distinct `live_session` scopes, each with an `on_mount` hook (§8): `:public`, `:sighting`, `:member` (`MemberAuth :require_member` — approved member OR admin), `:admin` (`MemberAuth :require_admin`), `:require_authenticated_user`, and `:current_user`. The `/app` and `/admin` scopes additionally pipe through the `require_authenticated_user` plug so an anonymous HTTP request is rejected before the LiveView and the requested path is stored for return after login; the `on_mount` hooks repeat the check for socket navigation and add the membership test. Gate outcomes MUST be: anonymous → `/users/log-in`; authenticated without a profile, or pending/rejected/inactive → `/` with "You must be an approved member to access this page."; non-admin on `:admin` → `/` with "You must be an administrator to access this page."

Admin-only columns within a member-visible sighting view MUST be gated in the template AND the query layer, not merely hidden with CSS (§7.11, §9.1). LiveDashboard MUST require admin in every environment because it renders the application environment (§24).

## 4. Membership state machine

States: `pending`, `approved`, `rejected`, `inactive`. Transitions: `pending → approved`; `pending → rejected`; `approved → inactive`; `inactive → approved`; `rejected → pending`. Every other pair MUST return `{:error, :illegal_transition}` and write nothing. All transitions are admin-only (`Members.transition_status/4` takes the acting `%User{}`), and each writes a `membership_audit` row (`actor_user_id`, `from_status`, `to_status`, `reason`, `inserted_at`) in the same transaction. `reason` MUST be present for `→ rejected` and `→ inactive`; it MAY be null otherwise.

A transition to any status other than `approved` MUST delete the member's position assignments in the same transaction, so a deactivated or rejected member never shows as holding a position and position-derived admin access ends with the status. Only approved members may gain positions; removals are allowed for any status as defense in depth (§7.20).

New registrations create the `users` row and a `pending` member profile in one transaction (§9.2). Only `approved` members pass the `:member` on_mount gate; admins pass it regardless of profile. When a new account confirms (first magic-link login) and has a pending profile, holders of positions flagged `notify_on_new_member` MUST be emailed (§27).

## 5. Template baseline and repository layout

The project was bootstrapped from the `geowa4/base-phoenix` template (Appendix A). The template's rename task (`mix mc_emcomm.rename --otp mc_emcomm --module McEmcomm`) ran once and deleted itself; references to it in `fly.toml`, DEPLOY.md, and `test/deploy_workflow_test.exs` are historical and MUST be read as such. The LICENSE is MIT, copyright Monroe County EmComm.

Documentation is split by audience and MUST stay that way:
- `README.md` — the pitch: what the project is, who it serves, and where the detail lives.
- `SPEC.md` (this file) — the technical specification.
- `CONTRIBUTING.md` — Setup, Testing, Database & migrations, Inbound webhooks, Observability & health, Deployment (what a contributor must respect), Configuration, Privacy & retention, Sprites, Add-ons.
- `DEPLOY.md` — the operator reference: first deploy, custom domain, continuous deployment, runbook (first administrator, resetting two-factor, rotating the database credential).
- `AGENTS.md` — conventions for humans and coding agents plus the managed `usage_rules` block; `CLAUDE.md` and `GEMINI.md` each contain the single line `@AGENTS.md`; CI and `mix prepush` verify both bridges.

Toolchain versions are pinned in `mise.toml` (Erlang 28.3.3, Elixir 1.20.3-otp-28); CI and the Dockerfile MUST use the same majors. The old Hugo site lives at `monroecountyemcomm.org/` in the working tree as its own git repository, gitignored, kept only as a content reference.

## 6. Architecture & contexts

Phoenix ~> 1.8.11; Phoenix LiveView ~> 1.2.9 (colocated hooks and CSS in use); Elixir 1.20 / OTP 28; Bandit; Ecto SQL + Postgrex with `geo_postgis` types (`McEmcomm.PostgrexTypes`); PostgreSQL 17 with PostGIS and citext.

Contexts (`lib/mc_emcomm/`):
- **Accounts** — users, tokens, magic-link and password login, sudo mode, `is_admin`, TOTP and recovery codes, `Scope`.
- **Members** — profile, QTH point, emergency contact, status state machine and audit, positions and holders, call-sign search, new-member notification recipients, deletion cascade.
- **Capabilities / Courses / Certifications** — admin catalogs plus per-member records; certifications carry a prerequisite course and a task-book flag.
- **Assets** — inventory, Crockford `public_id`, image.
- **Sightings** — the three-update-point lifecycle, crawler detection, session binding, member/admin projections, retention scrub.
- **Operations** — operations, named geofenced locations, attachments, attendance, PostGIS geofence matching.
- **Locations** — the admin catalog of default (rally-point) locations.
- **Net** — sessions, check-ins with location snapshots, net control, leave/return, PubSub, APRS check-ins and filter inputs.
- **Aprs** (`Client`, `Filter`, `Packet`) — one receive-only APRS-IS connection.
- **Content** — resources documents; public pages render fixed copy.
- **Storage** (`Storage`, `Storage.Client` behaviour, `Storage.S3`) — presigned Tigris access.
- **Inbound** — Resend webhook dedupe and a no-op extension point.
- **Health.Probe**, **RetentionScrubber**, **Release**, **PromEx**.

Supervision tree (`McEmcomm.Application`, `:one_for_one`), in order: `PromEx`, `McEmcommWeb.Telemetry`, `Repo`, `DNSCluster`, `Phoenix.PubSub` (`McEmcomm.PubSub`), `Task.Supervisor` (`McEmcomm.TaskSupervisor`), then three conditionally started singletons — `Health.Probe` (`:start_health_probe`), `RetentionScrubber` (`:start_retention_scrubber`), `Aprs.Client` (`:start_aprs_client`), all `false` in test with documented reasons — then `McEmcommWeb.Endpoint` and a second private Bandit listener serving `McEmcommWeb.MetricsEndpoint` on `:metrics_port`. OpenTelemetry handlers for Phoenix (with LiveView), Bandit, and Ecto are attached before the tree starts.

Web layer (`lib/mc_emcomm_web/`): router with the pipelines in §8; `UserAuth` (phx.gen.auth plus the pending-two-factor layer), `MemberAuth` (member/admin on_mount hooks and the `require_admin_user` plug), `ActiveNet` (keeps `@active_net` current in every live_session); plugs `ContentSecurityPolicy`, `RecordSighting`, `CacheRawBody`, `TraceContext`, `VerifyResendSignature`; controllers for the home page, health, SEO files, sessions, and the webhook; components `CoreComponents`, `Layouts`, `MapComponents`; helpers `MapHelpers`, `ParamHelpers`; and the LiveViews of §9. Client code is `assets/js/app.js` plus hooks `LeafletMap`, `LeafletPicker`, `Modal`, `SightingClient`, `ThemeToggle`, the `S3` uploader, and three colocated hooks declared inline in templates: `.CopyIcs` (calendar), `.ResetOnSave` (net check-in form), `.SortableRows` (position drag reordering).

## 7. Data model

All tables carry `id` (bigserial), `inserted_at`, `updated_at` (`utc_datetime`) unless noted. Enums are stored as `:string` with `Ecto.Enum` (Elixir-side only). The first migration MUST enable `citext` and `postgis`. Point columns are `geography(Point,4326)`; `members.qth_point`, `operation_locations.point`, and `sightings.point` MUST have a GiST index (`net_checkins.location_point` and `default_locations.point` do not — they are never searched spatially). Fields set programmatically MUST NOT appear in `cast/3`: `users.is_admin`, the TOTP columns, `net_sessions.net_control_member_id`, `net_checkins.aprs_call_sign` and its location snapshot on update, `sightings.verified`, `member_courses.verified`, `member_certifications.verified`, and every `*_id` a context resolves itself.

### 7.1 `users`, `users_tokens`, `users_recovery_codes`

| Column | Type | Constraints |
|---|---|---|
| `email` | citext | unique, not null |
| `hashed_password` | string | nullable (magic-link-only accounts); Argon2id |
| `confirmed_at` | utc_datetime | nullable |
| `is_admin` | boolean | not null, default `false`; no cast path |
| `totp_secret` | binary | nullable; redacted; set only on confirmed enrollment |
| `totp_confirmed_at` | utc_datetime | nullable; non-null means TOTP is on |
| `totp_last_used_at` | utc_datetime | nullable; replay guard |

`users_tokens`: `user_id` (FK, delete_all), `token` binary, `context` string (`session`, `login`, `change:<email>`), `sent_to`, `authenticated_at`, `inserted_at` only; unique `(context, token)`; index `user_id`. Session tokens are 32 random bytes stored raw (the cookie is signed), valid 14 days; magic-link tokens are SHA-256-hashed, valid 15 minutes, and require `sent_to == user.email`; email-change tokens are valid 7 days.

`users_recovery_codes`: `user_id` (FK, delete_all), `hashed_code` binary (SHA-256, redacted), `used_at` (non-null means spent), `inserted_at` only; unique `(user_id, hashed_code)`. Eight codes per batch, 80 bits each, formatted `xxxx-xxxx-xxxx-xxxx` in lowercase base32 without ambiguous characters.

### 7.2 `members`

| Column | Type | Constraints |
|---|---|---|
| `user_id` | FK → users (delete_all) | not null, unique |
| `call_sign` | citext | nullable; trimmed and upcased; ≤ 16 chars; unique partial (`members_call_sign_index`, where not null) |
| `name` | string | not null |
| `qth_address` | text | nullable |
| `qth_point` | geography(Point,4326) | nullable; member-set by map click or typed coordinates |
| `license_class` | enum `technician\|general\|amateur_extra\|advanced\|novice` | nullable |
| `status` | enum `pending\|approved\|rejected\|inactive` | not null, default `pending` |
| `emergency_contact_name` | string | nullable; ≤ 160 |
| `emergency_contact_phone` | string | nullable; ≤ 32; MUST match `^\+?(?=.*[0-9])[0-9 ().-]+$` |
| `emergency_contact_relation` | string | nullable; ≤ 80 |

Indexes: unique `user_id`; unique partial `call_sign`; GiST `qth_point`; btree `status`. There is **no `role` column**; leadership is relational (§7.19–§7.20). The emergency contact is optional as a whole, but once any of its three fields is present the name and phone MUST be required; blank and whitespace-only values MUST be stored as null.

### 7.3 `membership_audit`

| Column | Type | Constraints |
|---|---|---|
| `member_id` | FK → members (delete_all) | not null |
| `actor_user_id` | FK → users (**on_delete nothing**) | not null |
| `from_status` / `to_status` | string | not null |
| `reason` | text | required when `to_status` ∈ {`rejected`, `inactive`}; else nullable |
| `inserted_at` | utc_datetime_usec | not null, default `now()` (no `updated_at`) |

Index: `member_id`. `actor_user_id` is `nothing` so deleting a member never orphans audit rows they wrote about others.

### 7.4 `capabilities` (admin catalog)

`name` citext not null unique; `code` string nullable; `description` text nullable (shown under the name on the profile); `active` boolean not null default `true`.

### 7.5 `member_capabilities`

`member_id`, `capability_id` (both FK, delete_all, not null); `notes` text. Unique `(member_id, capability_id)`.

### 7.6 `courses` (admin catalog)

Same shape as `capabilities` (`code` e.g. `IS-100`, `AUXCOMM`).

### 7.7 `member_courses`

`member_id`, `course_id` (FK, delete_all); `completed_on` date; `evidence_key` / `evidence_filename` / `evidence_content_type` (Tigris object); `verified` boolean not null default `false`, admin-set through a separate `verify_changeset`. Unique `(member_id, course_id)`.

### 7.8 `certifications` (admin catalog)

`name` citext unique; `code` (e.g. `AUXC`, `COML`, `COMT`); `description`; `prerequisite_course_id` FK → courses (**nilify_all**, indexed); `requires_task_book` boolean not null default `true`; `active` boolean not null default `true`.

### 7.9 `member_certifications`

`member_id`, `certification_id` (FK, delete_all); `issued_on`, `expires_on` dates; `task_book_key` / `_filename` / `_content_type` (completed Position Task Book); `certificate_key` / `_filename` / `_content_type` (credential); `verified` (admin-set via `verify_changeset`); `notes`. Unique `(member_id, certification_id)`.

### 7.10 `assets`

`public_id` char(6) not null unique — six Crockford base32 characters (`0-9A-HJKMNP-TV-Z`, no I/L/O/U), generated with up to ten collision retries and validated by `^[0-9A-HJKMNP-TV-Z]{6}$`; `name` not null; `description`; `image_key` / `image_filename` / `image_content_type`; `active` boolean not null default `true`.

### 7.11 `sightings`

Lifecycle fields are grouped by the update point that writes them (§9.1).

**Identity and visit (update point 0, HTTP mount)** — `asset_id` FK → assets (delete_all) not null; `session_token` string not null (24 random bytes, url-safe base64, stored in the plug session); `visited_at` utc_datetime_usec not null; `remote_ip` inet (`EctoNetwork.INET`); `fly_region`; `user_agent` text; `sec_ch_ua`; `sec_ch_ua_platform`; `sec_ch_ua_mobile`; `accept_language`; `referer` text; parsed `browser_name`, `browser_version`, `os_name`, `os_version`, `device_type` (ua_inspector with client hints; bots record the bot name and `device_type = "bot"`; `:unknown` maps to null).

**Client environment (update point 1, socket connect)** — `connected_at`; `timezone`; `screen_w`; `screen_h` (integers); `device_pixel_ratio` float; `languages` `{array, string}`; `connection_type`; `touch` boolean.

**Geolocation (update point 1, after permission)** — `located_at`; `point` geography; `accuracy`, `altitude`, `heading`, `speed` floats; `geo_denied` boolean not null default `false`.

**Submission (update point 2, form submit)** — `submitted_at`; `call_sign` citext (trimmed, upcased); `member_id` FK → members (nilify_all); `claimed_responsibility` boolean not null default `false`; `note` text; `verified` boolean not null default `false` (admin-only, written through `Sightings.verify/2`); `operation_id` FK → operations (nilify_all); `operation_location_id` FK → operation_locations (nilify_all).

**Retention** — `scrubbed_at` utc_datetime_usec nullable.

Indexes: `asset_id`; `member_id`; `operation_id`; `session_token`; `visited_at`; GiST `point`. Columns in the first three groups are admin-only in every query and view: `Sightings.list_for_asset_member_view/1` MUST select only the submission group (plus ids and timestamps) and only rows with a non-null `submitted_at`; `list_for_asset_admin_view/1` returns whole rows. A submitter MUST NOT be able to set `verified`, `member_id`, `operation_id`, or `operation_location_id` (`submit/3` allow-lists `call_sign`, `note`, `claimed_responsibility`).

### 7.12 `operations`

`title` not null; `description`; `starts_at`, `ends_at` utc_datetime not null with check `ends_at_after_starts_at`; `visibility` enum `public|members` not null default `members`; `created_by_id` FK → users (on_delete nothing) not null. Indexes: `starts_at`, `visibility`.

### 7.13 `operation_locations`

`operation_id` FK (delete_all) not null; `name` not null (defaults to `"Primary Site"` when the operation is created with exactly one unnamed location); `point` geography **not null**; `geofence_radius_m` integer not null default `500`; `notes`; `position` integer not null default `0` (preload order). Indexes: `operation_id`; GiST `point`; unique `(operation_id, name)`.

### 7.14 `operation_attachments`

`operation_id` FK (delete_all); `key`, `filename`, `content_type` not null; `description` text **not null** with check `description_not_empty` (`length(btrim(description)) > 0`); `uploaded_by_id` FK → users (on_delete nothing). Index `operation_id`.

### 7.15 `operation_attendance`

`operation_id` FK (delete_all); `member_id` FK → members (delete_all); `source` enum `manual|asset_checkin|admin` not null; `sighting_id` FK → sightings (nilify_all), set when `source = asset_checkin`; `recorded_at` utc_datetime_usec not null. Unique `(operation_id, member_id)`; `record_attendance/4` upserts with `on_conflict: :nothing`, so repeat scans and repeat clicks are no-ops.

### 7.16 `net_sessions`

| Column | Type | Constraints |
|---|---|---|
| `started_by_member_id` | FK → members (**on_delete nothing**) | not null; blocks member deletion (§20) |
| `net_control_member_id` | FK → members (nilify_all) | nullable; display-only role, never cast |
| `operation_id` | FK → operations (nilify_all) | nullable |
| `name` | string | required by the changeset; defaults to the start date `YYYY-MM-DD` |
| `aprs_keyword` | citext | not null; single word, 2–32 chars, no spaces |
| `started_at` | utc_datetime | not null |
| `ended_at` | utc_datetime | nullable; null means on the air |
| `notes` | text | nullable |

Indexes: `started_at`; `operation_id`; unique partial `aprs_keyword` where `ended_at IS NULL` (`net_sessions_active_aprs_keyword_index`, message "is already used by an active net") so an APRS packet routes unambiguously; ended nets may reuse keywords.

### 7.17 `net_checkins`

| Column | Type | Constraints |
|---|---|---|
| `net_session_id` | FK → net_sessions (delete_all) | not null |
| `call_sign` | citext | not null; trimmed, upcased |
| `aprs_call_sign` | citext | nullable; full station id with SSID (`K4GWA-4`); non-null marks the station APRS-tracked |
| `member_id` | FK → members (nilify_all) | nullable; matched by call sign |
| `location_name` | string | nullable; snapshot label (`QTH`, `APRS`, or a catalog/operation location name) |
| `location_point` | geography | nullable; snapshot copy, never a reference |
| `notes` | text | nullable |
| `recorded_at` | utc_datetime_usec | not null |
| `ended_at` | utc_datetime_usec | nullable; each stint on the net is its own row |

Indexes: `net_session_id`; `member_id`; partial `(net_session_id, call_sign)` where `ended_at IS NULL` (the open-check-in lookup made for every APRS packet).

### 7.18 `documents` (Resources)

`title`, `key`, `filename`, `content_type` not null; `members_only` boolean not null default `true`; `active` boolean not null default `true`; `position` integer not null default `0`.

### 7.19 `positions` (leadership catalog)

`name` string not null unique; `sort_order` integer not null unique with check `sort_order_positive` (`> 0`); `grants_admin` boolean not null default `false`; `notify_on_new_member` boolean not null default `false`. The table ships **empty** in production — admins manage it at `/admin/positions`; dev seeds create the nine-seat catalog (§19).

### 7.20 `member_positions`

`member_id` FK → members (delete_all); `position_id` FK → positions (delete_all). **Unique index on `position_id` alone** — every position is single-holder as a database fact; assigning a held position is a takeover performed in the same transaction. Index `member_id`. A member MAY hold several positions.

### 7.21 `default_locations`

`name` citext not null unique; `point` geography not null; `position` integer not null default `0`. The admin catalog of named rally points offered as a net check-in location and used as APRS filter centers (§14).

### 7.22 `webhook_events`

`svix_id` string not null unique; `event_type` string; `inserted_at` only. Only the delivery id and event type are persisted, never email content.

### 7.23 Referential integrity summary

`on_delete: :delete_all` — users_tokens, users_recovery_codes, members.user_id, member_positions (both), membership_audit.member_id, member_capabilities/member_courses/member_certifications (both sides), operation_locations, sightings.asset_id, operation_attachments.operation_id, operation_attendance (both), net_checkins.net_session_id. `nilify_all` — certifications.prerequisite_course_id, sightings.{member_id, operation_id, operation_location_id}, operation_attendance.sighting_id, net_sessions.{net_control_member_id, operation_id}, net_checkins.member_id. `nothing` — membership_audit.actor_user_id, operations.created_by_id, operation_attachments.uploaded_by_id, net_sessions.started_by_member_id.

### 7.24 Migration history

Pre-launch history was squashed into one baseline (`20260831000000_create_initial_schema`) that creates the schema in its intended shape. Three expand-only migrations followed: `20260903111135_add_totp_to_users`, `20260903140316_add_notify_on_new_member_to_positions`, `20260904000133_add_emergency_contact_to_members`. From here on every change MUST follow the expand-contract rules in CONTRIBUTING.md § Database & migrations (blue-green runs old and new code against one database; concurrent indexes outside a transaction; `NOT VALID` then `VALIDATE` for check constraints; migrations run in production only via `McEmcomm.Release.migrate/0`).

## 8. Routes & live_sessions

Pipelines: `:browser` (accepts html, session, live flash, root layout, CSRF, secure browser headers, `ContentSecurityPolicy`, `cache-control: no-store`, `fetch_current_scope_for_user`); `:record_sighting` (`x-robots-tag: noindex, nofollow` then `RecordSighting`); `:resend_webhook` (json + `VerifyResendSignature`); `:dev_browser` (dev build only, no CSP, for the Swoosh mailbox). Every `live_session` ends with `McEmcommWeb.ActiveNet` so `@active_net` exists everywhere.

| Path | Kind | Pipeline(s) | live_session / on_mount | Module | Tier |
|---|---|---|---|---|---|
| `/` | GET | browser | — (controller) | `PageController :home` | public |
| `/about`, `/training`, `/resources`, `/calendar`, `/donations` | live | browser | `:public` — `mount_current_scope` | `PublicLive.*` | public |
| `/operations`, `/operations/:id` | live | browser | `:public` | `OperationLive.PublicIndex`, `PublicShow` | public (public visibility only) |
| `/a/:public_id/s` | live | browser, record_sighting | `:sighting` — `mount_current_scope` | `SightingLive.Show` | public, noindex |
| `/app` | live | browser, require_authenticated_user | `:member` — `MemberAuth :require_member` | `AppLive.Dashboard` | member/admin |
| `/app/profile` | live | idem | `:member` | `AppLive.Profile` | member/admin |
| `/app/operations`, `/app/operations/:id` | live | idem | `:member` | `OperationLive.Index`, `Show` | member/admin |
| `/app/inventory`, `/app/inventory/:public_id` | live | idem | `:member` | `InventoryLive.Index`, `Show` | member/admin (admin sees more) |
| `/app/net`, `/app/net/:id` | live | idem | `:member` | `NetLive.Console`, `Show` | member/admin |
| `/admin` | live | browser, require_authenticated_user | `:admin` — `MemberAuth :require_admin` | `AdminLive.Dashboard` | admin |
| `/admin/members` | live | idem | `:admin` | `AdminLive.MemberIndex` | admin |
| `/admin/positions` | live | idem | `:admin` | `AdminLive.PositionIndex` | admin |
| `/admin/operations`, `/admin/operations/new`, `/admin/operations/:id/edit` | live | idem | `:admin` | `AdminLive.OperationIndex` (`:index`, `:new`, `:edit`) | admin |
| `/admin/inventory` | live | idem | `:admin` | `AdminLive.InventoryIndex` | admin |
| `/admin/capabilities`, `/admin/courses`, `/admin/certifications` | live | idem | `:admin` | `AdminLive.CapabilityIndex`, `CourseIndex`, `CertificationIndex` | admin |
| `/admin/locations` | live | idem | `:admin` | `AdminLive.DefaultLocationIndex` | admin |
| `/admin/documents` | live | idem | `:admin` | `AdminLive.DocumentIndex` | admin |
| `/users/settings`, `/users/settings/confirm-email/:token`, `/users/settings/two-factor` | live | browser, require_authenticated_user | `:require_authenticated_user` — `require_authenticated` (+ module-level `require_sudo_mode`) | `UserLive.Settings`, `TwoFactor` | authenticated, sudo |
| `/users/update-password` | POST | browser, require_authenticated_user | — | `UserSessionController :update_password` | authenticated, sudo |
| `/users/register`, `/users/log-in`, `/users/log-in/:token`, `/users/two-factor` | live | browser | `:current_user` — `mount_current_scope` | `UserLive.Registration`, `Login`, `Confirmation`, `TwoFactorChallenge` | anonymous / pending-2FA |
| `/users/log-in`, `/users/two-factor` | POST | browser | — | `UserSessionController :create`, `:verify_two_factor` | anyone / pending-2FA |
| `/users/log-out` | DELETE | browser | — | `UserSessionController :delete` | anyone |
| `/robots.txt`, `/sitemap.xml` | GET | none | — | `SeoController` | public, `cache-control: public, max-age=3600` |
| `/healthz/live`, `/healthz/ready`, `/healthz/version` | GET | none | — | `HealthController` | public, `no-store` |
| `/webhooks/resend` | POST | resend_webhook | — | `WebhookController :resend` | signature-gated |
| `/dev/dashboard` | live_dashboard | browser, require_authenticated_user, require_admin_user | its own | `Phoenix.LiveDashboard` (nonce-aware) | admin, every environment |
| `/dev/mailbox` | forward | dev_browser | — | `Plug.Swoosh.MailboxPreview` | dev build only |

## 9. LiveViews & UX flows

### 9.1 Sighting-first QR flow (three update points)

The QR SVG (eqrcode, rendered through `raw/1` from server-built strings only) MUST encode a sighting URL, never a plain asset page: `{MC_EMCOMM_QR_BASE_URL}/a/{public_id}/s`. `MC_EMCOMM_QR_BASE_URL` is the canonical public origin with no trailing slash and MUST equal `PHX_HOST`'s origin (DEPLOY.md § Custom domain).

**Update point 0 — HTTP mount (`Plugs.RecordSighting`, before the LiveView).** A sighting row MUST be created from the disconnected conn so the visit is recorded even if the WebSocket never connects. Captured: `remote_ip` (read `Fly-Client-IP` first; fall back to the first `X-Forwarded-For` address, then `conn.remote_ip`), `fly_region`, raw `user_agent`, the three `sec-ch-ua*` client hints, `accept_language`, `referer`, and a fresh `session_token`; `visited_at` is set; ua_inspector fills the parsed browser/OS/device columns. The plug MUST write **nothing** for a crawler or link-preview user agent (`Sightings.crawler_user_agent?/1`: a literal pattern for bot/crawl/spider/slurp/fetch/preview/scan/facebookexternalhit OR ua_inspector's bot database), for an unknown `public_id`, or for a deactivated asset; in those cases it MUST also clear any `sighting_id` / `sighting_session_token` left in the session by an earlier scan, and a crawler is redirected to `/`. The sighting id and token are stored in the plug session so both LiveView mounts find the same row.

**Update point 1 — socket connect (`SightingClient` hook).** Pushes `client_env` with `timezone` (`Intl.DateTimeFormat().resolvedOptions().timeZone`), `screen_w`/`screen_h`, `device_pixel_ratio`, `languages`, `connection_type` (if `navigator.connection`), and `touch`; the row is UPDATED and `connected_at` set. The hook then requests Geolocation (`enableHighAccuracy`, 10 s timeout); on grant it pushes `geolocation` with `lat`/`lng`/`accuracy`/`altitude`/`heading`/`speed` and the row is UPDATED with `point` and `located_at`; on deny, or when the API is absent, it pushes `geolocation_denied` and `geo_denied = true`.

**Update point 2 — form submit.** `call_sign` (required; prefilled from the logged-in member's call sign), optional `note`, `claimed_responsibility`. The row is UPDATED with `submitted_at`, `member_id` (the logged-in member if any, else an **approved** member matched case-insensitively by call sign), and the geofence-matched `operation_id`/`operation_location_id` when the sighting has a point (§10). If the linked member is approved and an operation matched, an `operation_attendance` row with `source = asset_checkin` and the `sighting_id` MUST be created.

The LiveView MUST accept only the sighting that this session's scan of **this** asset created: `Sightings.get_for_session/3` matches the asset id and compares the token in constant time; a missing sighting flashes "Something went wrong recording your visit. Please rescan the QR code." and redirects home. The page MUST render ONLY the asset image, the asset name and description, and the sighting form (or a `role="status"` "Thanks — this sighting has been recorded." once submitted); it sets `noindex`. Recent sightings, the sighting log, maps, and all metadata are members/admin-only at `/app/inventory/:public_id`; IP/UA/client-hint/geolocation columns are admin-only.

### 9.2 Registration, login, confirmation, account

- **Registration** (`/users/register`, `#registration_form`): email, name, optional call sign; live validation; creates the user (no password, unconfirmed) and a `pending` member in one transaction; sends confirmation instructions; redirects to `/users/log-in` with "An email was sent to …". Duplicate emails show "has already been taken". A logged-in visitor is redirected to `/`.
- **Login** (`/users/log-in`): a magic-link form (`#login_form_magic`) whose response is identical for known and unknown emails, and a password form (`#login_form_password`) with a remember-me checkbox that posts to the session controller. Invalid credentials flash "Invalid email or password" without disclosing whether the address exists. In dev, when the mailer is `Swoosh.Adapters.Local`, `#local-mail-notice` links to `/dev/mailbox`. For an already-logged-in user the page enters re-authentication mode ("You need to reauthenticate"), hides Register, and prefills the email.
- **Confirmation** (`/users/log-in/:token`): an unconfirmed user sees "Confirm and stay logged in" (`#confirmation_form`); confirming sets `confirmed_at`, mints a session, and triggers the new-member notification (§27). A confirmed user sees the plain login form ("Keep me logged in on this device"). Tokens are single-use; reuse or an invalid token flashes "Magic link is invalid or it has expired." Login is required at confirmation as pre-stuffing defense and MUST NOT be weakened.
- **Sessions**: `log_in_user/3` renews the session (except when the same user re-authenticates), honors and deletes `user_return_to`, and sets `live_socket_id`; remember-me is a signed cookie `_mc_emcomm_web_user_remember_me` valid 14 days, `Secure` in production; a session token older than 7 days is reissued on the next request. Logout deletes the token, broadcasts `disconnect` to the user's LiveViews, and clears the cookie. Password changes expire every other token.
- **Account** (`/users/settings`, labelled "Account" in menus): change email (confirmation link to the new address, `#email_form`), change password (`#password_form`, 12–72 chars, rotates the session), and a two-factor status line with a link to enrollment. The settings and two-factor pages require **sudo mode**: the on_mount hook accepts an authentication at most 10 minutes old (`Accounts.sudo_mode?/2` defaults to 20 minutes for controller assertions); otherwise "You must re-authenticate to access this page."

### 9.3 Two-factor authentication (optional per user)

- **Enrollment** (`/users/settings/two-factor`, sudo): "Begin" generates a 20-byte secret held only in the LiveView, renders an `otpauth://` QR (`#two-factor-qr svg`, issuer "Monroe County ARES/RACES") and the base32 manual key (`#two-factor-secret`), and asks for a code (`#two_factor_confirm_form`). Nothing persists until a correct code confirms; then the secret, `totp_confirmed_at`, and `totp_last_used_at` are set and eight recovery codes are shown **once** (`#recovery-code-0..7`, dismissed with `#two-factor-recovery-codes-done`). When enabled the page shows the unused count (`#two-factor-recovery-count`), Regenerate (issues a fresh batch, invalidating the old), and Disable.
- **Challenge**: when TOTP is enabled, **both** password and magic-link logins are parked — the magic link is consumed by the primary factor, no session token or remember-me cookie is minted, and the browser is sent to `/users/two-factor`. The parked login (`:pending_two_factor` in the signed session) carries only `user_id`, `remember_me`, the success flash, a timestamp, and an attempt counter — never a secret. It expires after 600 seconds and locks after 5 invalid codes ("Too many invalid codes. Please log in again."). The challenge page (`#two_factor_form`) uses a numeric input for authenticator codes and toggles to a free-form input for recovery codes; it only posts. Codes are verified and sessions minted **only** in `UserSessionController.verify_two_factor/2`; LiveViews never verify codes. Six trimmed digits route to TOTP (single use per window via `totp_last_used_at`), anything else to recovery codes (spent atomically with a single `update_all`); a recovery-code login appends "You used a recovery code; N remaining." Password updates re-login with `:skip_two_factor` because the user is already in sudo mode. Operator reset: `McEmcomm.Release.disable_totp/1` (DEPLOY.md § Runbook).

### 9.4 Member dashboard (`/app`)

Links to My Profile, Operations, Inventory, and Net Console. Every `/app` page MUST redirect a user without an approved profile to `/`.

### 9.5 Profile (`/app/profile`)

- `#profile-form`: name, call sign (upcased on save), license class, QTH address, and the `#emergency-contact` section (name, phone, relation; trimmed; all-or-nothing per §7.2). Saves flash "Profile updated"; a partial emergency contact is rejected with field errors.
- `#qth-location`: a labelled section with a `map_picker` (`#qth-map`, `role="application"`) and its coordinate form (`#qth-map-coordinates`). A dropped pin (`point_selected`) or typed coordinates (`set_qth_point`) save the point **immediately**, independent of the profile form, and push `picker:set_point` so the pin follows; invalid coordinates flash the range message without saving. No quadrant is shown or stored.
- `#capabilities-section`: one full-row switch per active catalog capability (`input#capability-<id>` with `role="switch"`, `aria-labelledby` the name, `aria-describedby` the catalog description), saved instantly on toggle with a helper line saying so; claimed rows are tinted; each toggle announces "<name> added to/removed from your capabilities." through the flash live region.
- `#courses-section`: one row per active course with a "Completed on" date (real `<label for>`), an evidence file picker (one file, any type, `external:` presigned upload), the verified state, and a Save button whose accessible name includes the course name. Saving flashes "<name> saved."; failed saves show translated changeset errors; a rejected upload marks the picker `aria-invalid` with the reason beneath it.
- `#certifications-section`: one row per active certification with "Issued on", prerequisite status ("on record" / "not yet" for `prerequisite_course_id`, from `Certifications.prerequisite_met?/2`), two upload slots (Position Task Book, certificate), verified state, and a named Save button. `verified` is admin-set. Position holdings and admin status are not member-editable.
- Per-record upload names are atoms interpolated from ids; the ids MUST be narrowed with `ParamHelpers.known_id/2` to records the page rendered so an event payload cannot mint atoms or crash the process.

### 9.6 Admin dashboard and membership approval

`/admin` shows a pending-members badge ("N pending") and links to every admin page. `/admin/members` (`AdminLive.MemberIndex`) MUST show pending members in their own section (`#pending-members`, with an empty state) above the main `#members` table. Each row shows name, call sign, status, positions (a popover multi-select of checkboxes, `#positions-form-<id>`, whose trigger is labelled "Positions held by <name>: …"; assigning a held position takes it over; checkboxes for unheld positions are disabled for non-approved members), the emergency contact with a `tel:` link (`#emergency-contact-<id>`), and actions: Approve (one click), Reject and Deactivate (open `#reason-modal` / `#reason-form`; a reason is required and written to the audit row), Reactivate, Reopen, and Audit (opens `#audit-modal`, titled with the member's call sign, listing each transition as from → to, its timestamp, and its reason). All modals close on Cancel, backdrop click, and Escape.

### 9.7 Leadership positions (`/admin/positions`)

A table of positions in `sort_order` with, per row, Move up / Move down buttons (`#move-up-<id>`, `#move-down-<id>`; disabled at the ends; labelled "Move <name> up/down"), the holder or "Vacant", badges "admin" (`grants_admin`) and "notifies" (`notify_on_new_member`), Change holder, Edit, Delete. Rows can also be dragged (`reorder` hook on `#positions-rows`); a reorder whose id list no longer matches the catalog MUST be refused as stale ("The list changed underneath you"). Create/Edit open `#position-modal` (`#position-form`: name, sort order > 0, grants admin, notify on new member). Delete MUST be refused while held ("A member holds that position"). `#change-holder-<id>` opens `#holder-modal` with a call-sign search (`#holder-search-form`, partial and case-insensitive, **approved members only**, results in a polite live region) and a Vacate button. Holding an admin-granting position opens `/admin/*` and shows the Admin menu link; an ordinary position does not.

### 9.8 Catalog CRUD

`/admin/capabilities`, `/admin/courses`, `/admin/certifications`: inline forms (`#capability-form`, `#course-form`, `#certification-form`) with New / Edit / Cancel / Delete and validation; certifications include `prerequisite_course_id` and `requires_task_book`, and the list shows the prerequisite course name.

### 9.9 Default locations (`/admin/locations`)

Create, edit, delete named rally points with a `map_picker` (`#default-location-map`) and coordinate form (`#default-location-map-coordinates`); the pending point is echoed in text (`#default-location-pending-point`); out-of-range coordinates report "Enter a latitude from -90 to 90 …" and push no event; Save is disabled until a point exists (or an existing record is being edited), and editing without re-dropping a pin keeps the existing point.

### 9.10 Documents (`/admin/documents`)

Upload a document (`#document-form`: title, file via presigned POST, `members_only` defaulting to true), toggle Activate/Deactivate, delete (removes the row; object deletion is the operator's concern).

### 9.11 Inventory

- **Admin** (`/admin/inventory`): create, edit, delete assets (`#asset-form`; image upload limited to `.jpg .jpeg .png .webp`, one file); "QR code" renders the inline SVG of §9.1.
- **Member list** (`/app/inventory`): names and `public_id`s; each name MUST be a real link so the row works from the keyboard.
- **Detail** (`/app/inventory/:public_id`): members see "Recent activity" — submitted sightings (call sign, submission time, note, verified flag) from the member projection. The page links to the public sighting page and shows the presigned image. Admins additionally see "Sighting log" (every row, all columns) and "Sighting map" (`#asset-map`, `static_map`) with `#map-filter`: since a date (defaulting to the asset's last-seen date, `#map-filter-since`) or the last 5/10/20 located sightings, applied in SQL. A member MUST never see the filter, the map, or the admin columns. Unknown ids redirect to the list.

### 9.12 Operations

- **Admin** (`/admin/operations`, `/new`, `/:id/edit`): the index lists operations with real edit links; creating redirects to the edit page ("Operation created"). `#operation-form`: title, description, starts/ends, visibility. `#location-form`: name, geofence radius, a `map_picker` (`#location-map`) with coordinates (`#location-map-coordinates`) echoed in `#location-pending-point`; Add (disabled until a point exists) / Remove; a single location with a blank name becomes "Primary Site". `#attachment-form`: one file via presigned POST plus a **required** description. Delete removes the operation.
- **Member** (`/app/operations`): every visibility. Detail (`/app/operations/:id`): header with the time window, description, locations listed in text and drawn on a `static_map` with radius circles, attachments (description + filename, Download via a short-lived presigned URL; an id that matches nothing answers "no longer available" instead of crashing), attendance list with source, and "Mark my attendance" (`source = manual`, flash "Attendance recorded").
- **Public** (`/operations`): only `visibility = public`, title and start time, empty state "No upcoming public operations", and a link to the member portal. `/operations/:id` renders a public operation; a members-only or nonexistent id produces the **same** redirect to `/operations` ("That operation isn't public.") so existence does not leak.

### 9.13 Net console and net page

See §14. The console (`/app/net`) lists active and past nets and hosts `#start-net-form` (name prefilled with the operator's local date from the `tz_offset_minutes` connect param, required APRS keyword `#start-net-aprs-keyword`, optional operation `#start-net-operation`); the net page (`/app/net/:id`) is the live roster, map, and controls.

## 10. PostGIS design

PostGIS is used ONLY for storing points and for geofence matching. Matching MUST query `operation_locations` joined to operations whose `starts_at <= t <= ends_at` window contains the sighting time, using `ST_DWithin(location.point, sighting.point, location.geofence_radius_m)` on geography (meters), ordered by `ST_Distance`, limit 1, returning `{location, operation}` or nil. All searched point columns are GiST-indexed. No quadrant is computed geometrically; APRS filter radii are computed by the APRS-IS server, not PostGIS.

## 11. File storage

A private Fly Tigris bucket holds all uploads (asset images, course evidence, certification task books and certificates, operation attachments, documents). `McEmcomm.Storage` dispatches to a `Storage.Client` behaviour with three callbacks — `presign_upload/2`, `presign_download_url/1`, `delete_object/1` — implemented by `Storage.S3` over `ReqS3`. LiveView `allow_upload` MUST use `external:` with a presigned POST form from `ReqS3.presign_form/1` whose policy carries a `content-length-range` cap of 8,000,000 bytes (mirroring LiveView's default, because `external:` uploads bypass the server) and a one-hour expiry; the browser posts the file directly with the `S3` uploader. Viewing MUST use short-lived URLs from `ReqS3.presign_url/1` (300 s); deletes presign a 60 s DELETE. Keys are `<prefix>/<uuid>.<ext>`. Standard env vars `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_REGION`, `AWS_ENDPOINT_URL_S3` drive ReqS3 and `BUCKET_NAME` names the bucket; `AWS_ENDPOINT_URL_S3` is mirrored into `:storage_url` only so the CSP can name the bucket origin. Tests MUST stub the client (`McEmcomm.StorageMock`, Mox). Local development uses adobe/s3mock (which validates no signatures and ignores policy conditions — CONTRIBUTING.md § Setup).

## 12. Maps

Leaflet 1.9.4 is vendored (`assets/vendor/leaflet`, no npm) and bundled by esbuild with OpenStreetMap tiles from `MC_EMCOMM_MAP_TILE_URL`; marker images are served from `/images/leaflet/`. Two components (`McEmcommWeb.MapComponents`):
- `static_map` — read-only, `role="region"` with a required accessible name, driven by a `data-markers` JSON array of `{lat, lng, title, radius_m}`; draws a radius circle when `radius_m` is given; redraws on data change; the page MUST list the same places in text nearby.
- `map_picker` — one draggable marker, `role="application"` with a required accessible name and `aria-describedby` instructions, plus a latitude/longitude form that is the keyboard and screen-reader equivalent of clicking. Clicks push `point_selected`; the form pushes `set_point` (or a per-page event); the server answers either with `picker:set_point` so the pin follows. Coordinates are validated server-side (`MapHelpers.parse_coordinates/1`, ranges ±90/±180).

The app MUST comply with the OSM Tile Usage Policy: identifying User-Agent, "© OpenStreetMap contributors" attribution, never bulk-download or offline-cache tiles. The tile origin MUST appear in the CSP `img-src`.

## 13. Geocoding

Nominatim is OPTIONAL and currently unused (map-click and typed coordinates are primary). If enabled, the app MUST comply with the OSMF Nominatim Usage Policy: absolute maximum of 1 request per second; an identifying User-Agent (`MC_EMCOMM_NOMINATIM_USER_AGENT` exists for this); results cached; no autocomplete or systematic queries; attribution displayed. Therefore geocode server-side, rate-limit, cache, and never geocode per keystroke.

## 14. Net logger

**Starting.** Any approved member starts a net from the console with a name (blank → the start date), a required single-word APRS keyword unique among active nets (case-insensitive), and an optional operation. The starter is stamped as `started_by_member_id`, becomes the initial net control operator, and — if they have a call sign — is logged as the first check-in with their QTH snapshotted. `{:nets_changed, :session_started}` is broadcast.

**Check-ins** (`#checkin-form`: call sign, location select `#checkin-location`, notes). The call sign is matched to a member (any status) case-insensitively. The location is a **snapshot copy** resolved server-side from a client ref: blank/`qth` → the member's `qth_point` labelled "QTH"; `default:<id>` → a catalog location; `op:<id>` → an operation location, honored only when the net is assigned to that operation; anything else → no location. Editing the catalog later MUST NOT change recorded check-ins. After saving, the server pushes `checkin_saved` and a colocated hook clears the form and returns focus to the call-sign field. Check-ins broadcast `{:checkin_added, c}` on `net_session:<id>` and reach every viewer's roster and map.

**Leave and return.** Each stint is its own row: "leaving" sets `ended_at` on the open check-in (`#checkout-checkin-<id>`), returning is a fresh check-in, and the roster shows every stint with its duration. Checking out the net control operator vacates the role. **Editing** (`#edit-checkin-<id>` opens `#edit-checkin-modal`) corrects call sign (re-matching the member), notes, and the location snapshot (`blank` keeps, `default:<id>` replaces, `qth` re-snapshots, `none` clears); edits propagate over PubSub.

**Net control** (`#net-control`): display-only; any approved member may Take (`#take-net-control`, hidden for the current operator), Vacate (`#vacate-net-control`, shows "Vacant"), or Change via `#ncs-modal` (call-sign search over approved members). Deleting the member vacates it; ending the net keeps the last operator on record.

**Other controls**: rename inline (`#edit-net-name` / `#net-name-form`, broadcast), edit the APRS keyword (`#edit-net-aprs-keyword` / `#net-aprs-keyword-form`, same validation, read-only once ended), assign or clear the operation (`#edit-net-operation` / `#net-operation-form`, adds its locations to the check-in select), and End net, which ends every open check-in at the session's `ended_at` and removes the check-in form for every viewer. Ending is open to any approved member by design.

**Map** (`#net-map`, `static_map`): while live it shows operators currently on the net with a known location; once ended it becomes the record of everyone who checked in with a location, with repeat stints at the same spot collapsed to one pin. APRS-placed check-ins show a "Position via APRS · <station>" badge (`#checkin-aprs-<id>`).

**PubSub contract.** Per-session topic `net_session:<id>`: `{:session_ended, s}`, `{:session_renamed, s}`, `{:session_updated, s}`, `{:checkin_added, c}`, `{:checkin_updated, c}`. Global topic `nets`: `{:nets_changed, reason}` with reason ∈ `:session_started | :session_ended | :keyword | :operation | :checkin | :aprs_checkin` — the inputs of the APRS filter and of the header's active-net indicator (`ActiveNet` reacts only to start/end and halts the message; a LiveView needing the others attaches its own hook first).

**APRS check-ins.** `McEmcomm.Aprs.Client` holds one receive-only APRS-IS TCP connection (`MC_EMCOMM_APRS_SERVER` default `rotate.aprs2.net`, port `14580`, identifying call sign `MC_EMCOMM_APRS_CALLSIGN` default `WB2EOC`, passcode `-1` so it never transmits, radius `MC_EMCOMM_APRS_RADIUS_KM` default 25). It idles disconnected while no net is active; otherwise its server-side filter is one `r/<lat>/<lng>/<km>` term per distinct default-location and active-operation-location point plus one `b/<CALL-SSID>` budlist term per tracked station (`Aprs.Filter.build/3`; empty when there are no points; call signs that could break the line are dropped; a warning above 400 bytes). Filter changes are debounced 500 ms after `{:nets_changed, _}` and refreshed every 60 s; a connected socket receives an in-band `#filter` line; disconnects reconnect with exponential backoff (1 s → 60 s) and a 120 s idle timeout. `Aprs.Packet.position_report/1` accepts uncompressed, timestamped, compressed, and Mic-E positions (never status, message, object, item, telemetry, or weather packets) and yields `station`, base `call_sign` (upcased), `ssid`, `point`, `comment`. `Net.record_aprs_position/1` handles each active net in its own `FOR UPDATE` transaction on the session row (safe across blue-green overlap and a racing end): a comment containing the net's keyword (case-insensitive) checks the station in as a guest (`location_name "APRS"`, member linked by base call sign ignoring SSID) or **moves** the operator's existing open check-in to this station; a station already tracked keeps moving the pin without the keyword until it leaves or the net ends; other SSIDs of the same operator are ignored unless they send the keyword, in which case they take over the same check-in row; an ended net records nothing. Processing is idempotent and never raises on a bad line.

## 15. Public pages

Content parity with the former site is required. Home (controller-rendered: hero with the emblem, "Who we are", "What we do", meeting cadence, registration call to action), About (mission; `#leadership-list` rendering **every** position from `Members.list_positions/0` in `sort_order` with approved holders' name and call sign or an italic "Vacant"; meetings on the fourth Thursday monthly except July, August, and December; a "Weekly Net & Repeaters" section (`#weekly-net`, `#repeaters`) publishing the Thursday 7:00 PM local net on the primary repeater, the 2 m primary W2ARM (146.610 MHz, -0.6 MHz offset, PL 110.9 Hz, Cobbs Hill, FM and P-25), the 70 cm W2ARM (444.450 MHz, +5 MHz offset, PL 110.9 Hz), and a note that the callsign changed from N2MPE; services; membership; contact address; `#social-links`; emergency-communications disclaimer), Training (FEMA IS-100/200/700/800 links, ARRL and AuxComm training, a profile link shown only to logged-in visitors), Resources (`#drive-folder-link`; published documents with Download buttons; anonymous visitors MUST see neither the titles nor the files of members-only documents, only `#members-only-note`; every download is re-checked server-side before redirecting to a presigned URL), Calendar (Google Calendar embed in an iframe with a title, Subscribe link, `#copy-ics-btn` with a `role="status"` announcement, ICS link), Donations (Zeffy link, check address, in-person). Leadership confirmed the repeater and net details on 2026-09-04 (Appendix B); changes to them MUST come from leadership. Meta descriptions, canonical links, and structured data are specified in §26.

## 16. Deployment

Fly app `mc-emcomm`; env prefix `MC_EMCOMM_`. Full operator procedures are in DEPLOY.md; the following are requirements.

**Database.** Fly Managed Postgres, PostgreSQL 17 with PostGIS (`fly mpg create --pg-major-version 17 --enable-postgis-support`; fall back to 16 only if 17+PostGIS is unavailable in the region). `DATABASE_URL` is set by `fly mpg attach`. Credential rotation MUST use a `schema_admin` role (DEPLOY.md § Runbook).

**Object storage.** Private Tigris bucket (`fly storage create`), credentials as Fly secrets.

**Container.** Multi-stage Dockerfile (hexpm/elixir 1.20.3-erlang-28.3.3 on Debian trixie; runner debian-slim, user `nobody`), `mix ua_inspector.download` baked into the image so the parser databases ship with the release, `GIT_SHA` build arg exposed at `/healthz/version` and as the OTel `service.version`. Release `mc_emcomm` with `opentelemetry_exporter: :permanent` before `opentelemetry: :temporary`; `rel/overlays/bin/migrate` runs `McEmcomm.Release.migrate/0` as the release command, `bin/server` starts with `PHX_SERVER=true`; `rel/env.sh.eex` configures IPv6 distribution and `DNS_CLUSTER_QUERY` only when running on Fly.

**fly.toml.** `primary_region = "iad"`; `strategy = "bluegreen"`; readiness check `GET /healthz/ready` gates routing, liveness `GET /healthz/live`; `min_machines_running = 1` is mandatory (auto-stop would kill the probe, PromEx, the scrubber, and the APRS client); `[metrics] port 9091 path /metrics` is scraped over the private network and never published; `force_https`; `PHX_HOST`, `PORT=8080`, `METRICS_PORT` in `[env]`; 1 GB shared VM.

**Environment variables** (read in `config/runtime.exs`):

| Variable | Required | Default | Purpose |
|---|---|---|---|
| `DATABASE_URL` | prod | — | Repo |
| `SECRET_KEY_BASE` | prod | — | Endpoint |
| `PHX_HOST` | prod | `example.com` | Public origin for canonical/OG URLs, sitemap, emails |
| `MC_EMCOMM_QR_BASE_URL` | no | `http://localhost:4000` | Origin encoded in QR codes; MUST match `PHX_HOST` |
| `RESEND_API_KEY`, `MAIL_FROM`, `RESEND_WEBHOOK_SECRET` | prod | — | Outbound mail (Resend via Swoosh) and inbound signature |
| `BUCKET_NAME`, `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_REGION`, `AWS_ENDPOINT_URL_S3` | prod | — | Tigris (§11) |
| `MC_EMCOMM_SIGHTING_RAW_RETENTION_DAYS` | no | `90` | Retention scrub (§20) |
| `MC_EMCOMM_MAP_TILE_URL` | no | OSM tile endpoint | Leaflet tiles and CSP `img-src` |
| `MC_EMCOMM_NOMINATIM_USER_AGENT` | no | dev placeholder | §13 |
| `MC_EMCOMM_APRS_SERVER`, `_PORT`, `_CALLSIGN`, `_PASSCODE`, `_RADIUS_KM` | no | `rotate.aprs2.net`, `14580`, `WB2EOC`, `-1`, `25` | §14 |
| `METRICS_PORT` | no | `9091` | Private Prometheus listener |
| `OTEL_EXPORTER_OTLP_ENDPOINT` (+ `_HEADERS`, `_PROTOCOL`) | no | unset | Presence enables the OTLP trace exporter |
| `PORT`, `PHX_SERVER`, `POOL_SIZE`, `ECTO_IPV6`, `DNS_CLUSTER_QUERY`, `GIT_SHA` | no | template defaults | Runtime plumbing |

Production also uses JSON logs (`LoggerJSON.Formatters.Basic`) with `request_id`, `trace_id`, `span_id`; `force_ssl` excluding the health paths; `Secure` cookies.

**Continuous deployment.** `.github/workflows/deploy.yml` runs after a successful CI run of a push to the default branch from this repository (forks are excluded by construction), or on manual dispatch, deploys the verified commit with `flyctl deploy --remote-only --build-arg GIT_SHA=…`, and is inert until the `FLY_APP` repository variable and `FLY_API_TOKEN` secret exist. Concurrency never cancels a running blue-green rollout. The `production` environment SHOULD carry a custom branch policy limited to `trunk`. Merging to `trunk` ships.

## 17. CI

`.github/workflows/ci.yml` runs on push to `trunk`/`main` and on every pull request with `contents: read`. Job `test` uses a `postgis/postgis:17-3.5` service (geofence tests MUST run against real PostGIS) and runs, in order: `mix deps.get`, `mix audit` (hex.audit + deps.audit with the acknowledged advisory ids), `format --check-formatted`, `deps.unlock --check-unused`, `compile --warnings-as-errors`, `credo --strict`, `sobelow --config`, the `CLAUDE.md`/`GEMINI.md` bridge check, `usage_rules.sync --check`, ua_inspector database download when not cached, and `mix test --cover` (90% threshold). Job `dialyzer` runs `mix dialyzer --format github` in `:dev` with PLTs cached under `priv/plts`. `mix prepush` mirrors the whole pipeline locally (raising the open-files limit first) and is wired to `.githooks/pre-push`; `mix precommit` is the five-step subset. Local dev pins `postgis/postgis:17-3.6-alpine`; the minor-version difference from CI is a deliberate tolerance (same PostgreSQL major).

## 18. Testing

The stack is ExUnit, the Ecto SQL Sandbox, `Phoenix.LiveViewTest`, PhoenixTest, LazyHTML, Mox (storage only), StreamData, and Swoosh's test adapter. Requirements:
- Geofence/PostGIS tests MUST run against real PostGIS, not a mock. `ReqS3.presign_form/1` and `presign_url/1` MUST be stubbed through `McEmcomm.StorageMock`.
- Sighting-flow tests MUST cover the disconnected HTTP-mount insert, crawler skipping, the connect update, geolocation grant/deny, session binding to the asset, and the submit update including the `operation_attendance` row with its `sighting_id`, and MUST prove the member projection never selects the admin-only columns.
- Membership: table-driven tests for every legal and illegal transition with audit assertions, position vacating, and the deletion cascade. Positions: single-holder takeover, approved-only assignment, stale reorder, guarded delete, admin derivation through `Scope`.
- Permissions: one authorization test per `live_session` gate, plus LiveDashboard.
- Accounts: magic link, password, sudo mode, token reissue, TOTP enrollment/verification/replay, recovery-code single use, pending-two-factor expiry and lockout, user-enumeration parity.
- Net: location snapshots, net control, leave/return, editing, ending, keyword rules, APRS parsing, filter strings, the client against a fake APRS-IS server, and the packet decision table.
- Accessibility assertions (§23) MUST be kept: skip link and main landmark, labelled nav, native disclosure menus, labelled theme toggle, new-tab notes, the on-air text alternative, input error wiring, modal labelling, hidden icons, switch semantics and labelled sections on the profile, named move buttons, `role="application"` maps with coordinate forms, real links in clickable rows, and the numeric-only challenge input toggling its pattern.
- Tests MUST assert against key element IDs and semantic selectors, never raw HTML. A test MAY be `async: true` only when it shares no mutable global state (the APRS client, the readiness flag, the mailer adapter swap, the storage-URL env, and `mix sync` are synchronous). Fixtures reach `approved` through a real admin transition; APRS keywords are unique per test.
- Coverage is enforced by CI at 90% with dev tooling, the release migrator, test scaffolding, and the real S3 client excluded.

## 19. Seeds

Idempotent dev seeds (`priv/repo/seeds.exs`, run by `mix ecto.setup` and `mix dev.server`) create: an admin account with an approved member profile and one fictional emergency contact; the nine-seat positions catalog (President, Vice-President, Secretary with `notify_on_new_member`, Treasurer, Emergency Coordinator, Assistant Emergency Coordinator, Director-at-Large 1–3; none grants admin); nine further fictional members mirroring the real roster's *shape* — every position filled except Assistant Emergency Coordinator (left vacant so About renders "Vacant"), one member holding Vice-President and Emergency Coordinator at once, two members without positions (one out of county), and one `pending` member — each approved through a real transition with fictional QTH points around Monroe County; the capabilities catalog (2m/70cm HT field-programmable, APRS, HF voice, with descriptions upserted on re-run); the courses catalog (AUXCOMM, IS-100, IS-200, IS-700, IS-800); the certifications catalog (AUXC with `prerequisite_course_id → AUXCOMM` and `requires_task_book`, COML, COMT); one members-only single-location operation (auto-named "Primary Site") and one public three-location operation; four default locations named NW/NE/SW/SE; and three sample assets with generated `public_id`s. Seeds create no sightings, nets, documents, or member training records. Real people MUST enter production only through the admin UI; the positions table is empty there until an admin creates it.

## 20. Privacy, retention & deletion

Member PII MUST never render on public routes; the only member data on a public page is the name and call sign of approved leadership holders. Emergency contacts are visible to the member and to admins only. Sighting IP/UA/client-hint/geolocation data is visible ONLY to admins and MUST be excluded from member-facing queries at the query layer. Raw sighting telemetry is retained for `MC_EMCOMM_SIGHTING_RAW_RETENTION_DAYS` (default 90), after which `McEmcomm.RetentionScrubber` — a supervised GenServer on an hourly `Process.send_after` timer, NO Oban — MUST null `remote_ip`, `user_agent`, the three client hints, `accept_language`, `referer`, `point`, `accuracy`, `altitude`, `heading`, `speed` and set `scrubbed_at`, retaining the parsed browser/OS/device columns, the client environment, `geo_denied`, the timestamps, and the whole submission group.

Member deletion (`Members.delete_member/1`) MUST: purge the member's Tigris objects (course evidence, task books, certificates); rely on `delete_all` for audit rows about the member, positions, capability/course/certification records, and attendance; de-link sightings (`member_id` → null) and net check-ins (`member_id` → null, `call_sign` text kept); vacate net control; leave the `users` row untouched so audit rows the person wrote about others keep their actor; and refuse with `{:error, :has_started_net_sessions}` when the member started any net, so net history is never orphaned.

Privacy-adjacent controls elsewhere: registration and login never reveal whether an email exists (§9.2); the `users` row's `totp_secret` and password are redacted in logs; the parked two-factor login carries no secrets (§9.3); every HTML response is `cache-control: no-store` (§24); crawlers never create sightings (§9.1).

## 21. Build history

The staged plan of the original specification is complete: Foundation; Members & membership; Catalogs; Storage & maps; Assets & sightings; Operations & geofence; Net logger; Hardening (retention scrub, privacy/deletion, CI PostGIS parity, Fly deployment). The thresholds it set were resolved as follows: the template provided no remote-IP plug, so `RecordSighting` reads `Fly-Client-IP` itself; ua_inspector's databases are downloaded in the Docker build and cached in CI rather than parsed lazily; MPG PG17+PostGIS is the documented path with PG16 as the fallback.

Changes after the initial implementation, in order, with the specification they altered:

| Date | Change | Effect on this specification |
|---|---|---|
| 2026-08-30 | Security review: sighting `verified` mass assignment closed, LiveDashboard behind admin, sighting session bound to its asset, Secure cookies, presign size cap; CSP with per-request nonce; members-only resource titles hidden from anonymous visitors; `mix deps.audit` and sobelow in CI; event ids through `ParamHelpers` | §3, §9.1, §11, §15, §17, §24 |
| 2026-08-30 | Public content ported from the Hugo site; the single `role` enum replaced by relational positions | §7.19–§7.20, §15 |
| 2026-08-30 | Migration history squashed into one baseline | §7.24 |
| 2026-08-30 | Template inbox demo removed; webhook endpoint kept as a no-op extension point | §6, §7.22 |
| 2026-08-30 | Header user dropdown; Register link; named net sessions defaulting to the operator's local date; inline net rename | §14, §25 |
| 2026-08-31 | `mix podman.up/down`, `mix dev.server`; health probe and scrubber not started in test | §6, CONTRIBUTING § Setup |
| 2026-08-31 | Responsive layout: hamburger nav below `lg`, scrolling tables, wrapping inline forms | §25 |
| 2026-08-31 | Sighting call-sign prefill; user-agent parsing wired up; sighting map filter | §9.1, §9.11 |
| 2026-08-31 | Check-in editing and leave/return with durations; the starter logged as the first check-in; check-in edit and member audit/reason forms moved into modals; form reset and refocus after saving a check-in | §14, §23 |
| 2026-08-31 | Positions made single-holder with a managed catalog, drag reordering, takeover, holder search; positions may grant admin; leaving approved status vacates positions; Admin link shown to position-derived admins | §3, §4, §7.19–§7.20, §9.7 |
| 2026-08-31 | `mix prepush` CI mirror and pre-push hook | §17 |
| 2026-09-01 | Every HTML response `no-store` | §24 |
| 2026-09-01 | Exercises renamed to operations | throughout |
| 2026-09-01 | Quadrants replaced by point locations: default-locations catalog, check-in location snapshots, nets assignable to operations, net control role, live on-net map | §7.2, §7.16–§7.17, §7.21, §9.9, §14 |
| 2026-09-01 | An ended net's map shows every located check-in | §14 |
| 2026-09-02 | APRS position reports check stations into nets | §7.16–§7.17, §14 |
| 2026-09-02 | `Release.promote_admin/1`; the EmComm emblem, favicons, and manifest | §16, §25, DEPLOY § Runbook |
| 2026-09-03 | Optional TOTP two-factor authentication with recovery codes and `Release.disable_totp/1` | §7.1, §9.3 |
| 2026-09-03 | Header emblem pulses while a net is on the air; Member Portal and Admin links moved into the user menu; Home link; brand link targets the active net; `/app` and `/admin` pipe through `require_authenticated_user` | §8, §25 |
| 2026-09-03 | Pending members sectioned atop the admin members page; new-member emails to flagged position holders | §9.6, §27 |
| 2026-09-03 | Search and link-preview metadata, robots.txt and sitemap; the sighting page kept out of indexes and crawler visits not recorded | §9.1, §26 |
| 2026-09-03 | Operator procedures moved to DEPLOY.md | §5 |
| 2026-09-03 | **Screen-reader and keyboard accessibility pass** across the layout, components, and every LiveView | §23 |
| 2026-09-03 | Optional emergency contact on the member profile | §7.2, §9.5 |
| 2026-09-03 | Profile capabilities, courses, and certifications tidied and made accessible | §9.5, §23 |
| 2026-09-04 | README trimmed to a pitch; contributor detail moved to CONTRIBUTING.md | §5 |
| 2026-09-04 | Spec rewritten as SPEC.md; leadership confirmed and the About page published the net schedule, repeaters, and fourth-Thursday meetings; `GEMINI.md` bridge guarded like `CLAUDE.md`; stale `ResendMock` coverage entry and PostgreSQL 18 wording removed | §5, §15, §17, §22 |

Two themes run through the history and are now requirements rather than afterthoughts: **authorization is enforced in the query and the context, not only in the template** (every security fix moved a check down a layer), and **every pointer-driven interaction has a keyboard and screen-reader equivalent** (§23).

## 22. Open questions / future work

Operational follow-ups: the positions catalog must be created by an admin on first deploy (§19); `.dialyzer_ignore.exs` is picked up by filename convention and is not referenced from `mix.exs`; the net page still calls `String.to_integer/1` directly on client-supplied ids in two handlers (`find_checkin/2` and `assign_operation`) instead of `ParamHelpers`; the client still configures `longPollFallbackMs: 2500` although the endpoint disables long polling. Future work: ICS-form generation from net logs; operation after-action report export; admin UI for marking sightings verified and for `source = admin` attendance; optional self-hosted Nominatim; FCC ULS call-sign lookup; per-user rate limiting of two-factor attempts (the counter is per cookie today); OAuth/OIDC via Assent if ever wanted (CONTRIBUTING.md § Add-ons).

## 23. Accessibility

Accessibility is a first-class requirement, not a polish step. The rules below are what the code and test suite enforce; new UI MUST follow them and the corresponding tests MUST be kept green.

**Landmarks and page structure.**
- Every page MUST begin with a skip link (`#skip-to-content`, off-screen until focused) targeting `main#main-content`, which carries `tabindex="-1"` so the jump actually moves focus.
- Site navigation MUST be a `<nav aria-label="Main">`; the page body is a single `<main>`; the footer is a `<footer>`. Sections that group related controls (profile capabilities, courses, certifications, QTH) MUST be `<section aria-labelledby>` with a visible heading.
- Every page sets a `page_title` rendered through `live_title` with the site suffix.

**Menus and disclosures.**
- The user menu and the mobile menu MUST be native `<details>/<summary>` disclosures with named toggles (`#user-menu-button` shows the user's display name; `#mobile-menu-button` has `aria-label="Menu"`). Global scripts close an open menu on Escape (returning focus to its summary), on an outside click, and when focus leaves it. The disclosure triangle is removed with CSS, never by replacing the element.

**Dialogs.**
- All dialogs MUST use the `<.modal>` component: a `<dialog>` opened with `showModal()` by the `Modal` hook so focus is trapped, Escape closes, and focus returns to the opener when the dialog leaves the DOM. It carries `aria-labelledby` pointing at its `<h2>` title; the backdrop is a real `<button aria-label="Close">`; every close path pushes the LiveView's `on_close` event exactly once, even when the server re-renders the dialog after a validation error.

**Forms and errors.**
- Every input MUST have a visible `<label for>` (or an `aria-label` where a label would be redundant, e.g. per-row file pickers named "<course> completion"). Inputs with errors MUST carry `aria-invalid="true"` and `aria-describedby` listing every error paragraph's id in order (`<id>-error-<n>`); valid inputs carry neither attribute. Selects and textareas follow the same rule. Upload errors render beneath the file picker the same way.
- Buttons that repeat across rows (Save, Edit, Delete, Move, Change holder, Log leaving, Edit check-in) MUST carry a per-row accessible name, either visible text plus an `.sr-only` suffix or an `aria-label` that names the record.
- Action-only controls MUST be `<button>`s, never `<a phx-click>` without an `href`. Navigation MUST be real links (`<a href>`), including inside clickable table rows, so a row works from the keyboard.
- The two-factor challenge uses `inputmode="numeric"` with a digits-only `pattern` for authenticator codes and drops the pattern in recovery-code mode.
- The capability toggles are `<input type="checkbox" role="switch">` with `aria-labelledby` (short name) and `aria-describedby` (catalog description), and a helper line explains that changes save instantly.

**Pointer-only interactions MUST have a non-pointer equivalent.**
- Every map picker pairs the Leaflet canvas (`role="application"`, accessible name, `aria-describedby` instructions) with a latitude/longitude form that does the same job and is validated server-side; read-only maps are `role="region"` with a name, and the page lists the same places in text.
- Position reordering offers Move up / Move down buttons beside drag-and-drop; the end-of-list buttons are `disabled`, not silently inert.
- Copy-to-clipboard buttons announce success in a `role="status"` region.

**Live regions and focus.**
- Flash messages render inside `#flash-group[aria-live="polite"]`; each flash is `role="alert"` with a labelled close button. Instant saves (capability toggles, course and certification saves) MUST announce through the flash region.
- Search results in modals (holder search, net control search) MUST render in an `aria-live="polite"` region, with the search input focused on open (`phx-mounted={JS.focus()}`).
- After a net check-in saves, focus MUST return to the call-sign field even though LiveView restores focus to the submit button after the ack (the colocated hook redirects it).

**Text alternatives and decoration.**
- Heroicons are `aria-hidden="true"`; every icon-only control carries an `aria-label`. The emblem image is decorative (`alt=""`) inside the brand link, whose text names the organization.
- The on-air state is conveyed in text: the brand link contains an `.sr-only` "(<net> is on the air)" and a `title`, not only the green glow; the emblem pulse honors `prefers-reduced-motion` by falling back to a static glow.
- External links that open a new tab include `<.new_tab_note />` ("(opens in a new tab)") inside the link text. Iframes and QR SVGs carry titles/names. Arrow glyphs in audit rows are `aria-hidden` with an `.sr-only` "to".
- Low-contrast secondary text (e.g. "Vacant") MUST be at least 70% opacity of the base content color.

**Keyboard focus.** `:where(a, button, summary, [tabindex]):focus-visible` MUST show a 2 px primary-color outline with offset on every interactive element, placed below daisyUI's own focus styles.

**Theme.** The color-theme toggle is a `role="group"` labelled "Color theme" of three named buttons (system/light/dark) whose `aria-pressed` the `ThemeToggle` hook keeps in step with the document's actual theme; both light and dark themes MUST keep their daisyUI contrast pairs.

## 24. Security hardening

- **Content-Security-Policy** (`Plugs.ContentSecurityPolicy`, per request): `default-src 'self'; base-uri 'self'; object-src 'none'; frame-ancestors 'self'; form-action 'self'; script-src 'self' 'nonce-<16 random bytes>'; style-src 'self' 'unsafe-inline'; font-src 'self' data:; img-src 'self' data: <tile origin> <storage origin>; connect-src 'self' <storage origin>; frame-src 'self' https://calendar.google.com`. `script-src` MUST stay nonce-only; `style-src` keeps `'unsafe-inline'` because Leaflet and LiveDashboard write style attributes. The only inline script is the theme bootstrap in the root layout, which carries the nonce; LiveDashboard receives it via `csp_nonce_assign_key`. The storage origin is omitted when no bucket is configured. The dev-only mailbox pipeline has no CSP.
- **Caching**: every HTML response and every health response MUST be `cache-control: no-store` (nonces, CSRF tokens, session cookies, and the sighting recording must never be served from a shared cache); fingerprinted static assets keep long-lived public caching; robots.txt and sitemap.xml are `public, max-age=3600`.
- **Transport and cookies**: `force_ssl` in production (health paths excluded for Fly's private checks); session and remember-me cookies `Secure` in production, `SameSite=Lax`; LiveView long-polling is disabled at the endpoint (`longpoll: false`) as defense in depth for CVE-2026-32689; WebSocket is the only transport regardless of the client's fallback setting.
- **Mass assignment**: submitters cannot set `verified` or any id on a sighting; `is_admin`, TOTP columns, net control, APRS station, and location snapshots have no cast path; catalog `verified` flags use separate changesets.
- **Event parameters**: ids from LiveView events go through `ParamHelpers.id/1` (nil rather than raise) and `known_id/2` (only records the socket rendered); unknown attachment/document ids are answered, not dereferenced.
- **Authorization depth**: `live_session` on_mount hooks plus HTTP plugs (§3); document downloads and net/position actions re-check on the server; LiveDashboard requires admin in every environment; public operation lookups do not leak existence.
- **Authentication**: Argon2id with `no_user_verify` on misses; identical responses for known and unknown emails; magic links single-use, 15 minutes, bound to the address they were sent to; two-factor parking with expiry and lockout; sudo mode for account changes.
- **Inbound webhook**: Svix-style verification implemented manually (HMAC-SHA256 over `id.timestamp.body`, `whsec_` key, ±300 s, constant-time compare, only `v1` signatures considered), raw body captured only for `/webhooks/*` and forwarded as `{:more, …}` so oversized bodies 413 instead of truncating; deliveries deduplicated on `svix-id`; processing asynchronous under `McEmcomm.TaskSupervisor`.
- **Supply chain**: `mix audit` (hex.audit + mix_audit) and `sobelow --config` (`exit: "low"`) run in CI and `mix prepush`; the acknowledged advisories (hackney via ua_inspector's offline download; gun/cowlib via the dev-only Sprites SDK) and sobelow findings (`Config.CSP`, `DOS.BinToAtom`, `Config.CSRFRoute`, `XSS.Raw`) are recorded with rationale in `mix.exs` and `.sobelow-conf` and MUST be revisited when the app grows a new `raw/1`, an unprotected route, or another interpolated atom.
- **Secrets**: never committed; all production secrets come from the environment in `config/runtime.exs`; MPG connection strings printed by `fly mpg` MUST be treated as tainted and rotated per DEPLOY.md.

## 25. Layout, navigation & theming

`Layouts.app/1` (attrs `flash`, `current_scope`, `active_net`) renders: the skip link; a `navbar` header whose brand (`#header-brand`: emblem + "Monroe County ARES/RACES") links to the most recently started net on the air (`/app/net/:id`) or `/` otherwise, with the emblem (`#header-emblem`, `data-active-net`) pulsing green via the `net-active` class while a net is live; a desktop nav (Home, About, Training, Resources, Operations, Calendar, theme toggle, then either the user menu or Register/Log in) shown from `lg` up; and a hamburger `#mobile-menu` below `lg` mirroring the same items. The user menu (`#user-menu`, labelled with call sign, else member name, else the email local part) holds Member Portal (`#user-menu-portal`), Admin (`#nav-admin`, when `Scope.admin?`), My Profile (approved members), Account, and Log out. `<main>` constrains content to `max-w-4xl`; the footer (`#site-footer`) lists Email Us, Facebook, X, Groups.io, and Calendar, the copyright year, and the tagline. Tables are wrapped in `overflow-x-auto`; inline forms wrap on narrow screens; inline form buttons align with their inputs.

`@active_net` is provided in every live_session by `McEmcommWeb.ActiveNet` (subscribes to the nets topic, recomputes on start/end) and by the home controller directly, so the indicator lights and darkens live on already-mounted pages, including the controller-rendered home page. A logged-out visitor who follows the brand link to a net is returned to it after logging in.

Theming: daisyUI 5 with a light theme (default) and a dark theme (`prefersdark`), Tailwind 4, Heroicons. The theme choice lives in `localStorage["phx:theme"]` and on `<html data-theme data-theme-source>`, applied before paint by the nonce-bearing inline script; "system" follows `prefers-color-scheme` live. The favicon set (ICO, SVG, Apple touch icon, manifest icons) is generated from the emblem, with `theme-color` `#222983`; `site.webmanifest` names the app "Monroe County ARES/RACES" (short name "MC EmComm", standalone display).

## 26. SEO & crawlers

Every page MUST emit a meta description (its own, falling back to the organization blurb), Open Graph (`og:type`, `og:site_name`, `og:title` "<title> · Monroe County ARES/RACES", `og:description`, `og:url`, a 512 px PNG `og:image`) and Twitter card tags (`summary`, `@MCARESNY`), and schema.org `Organization` JSON-LD (name, legal name, URL, logo, contact email, postal address, `sameAs` social profiles; `<` escaped). Indexable pages emit `<link rel="canonical">` built from the configured public origin and the request path with no query string; pages that set `noindex` (login, confirmation, two-factor challenge, the sighting page) emit `<meta name="robots" content="noindex, nofollow">` and no canonical. Registration is indexable. Public operations describe themselves from their own description (truncated to 160 characters).

`/robots.txt` (generated) MUST disallow `/a/`, `/app` and `/app/`, `/admin` and `/admin/`, `/dev/`, `/users/`, allow `/users/register`, and name the sitemap. `/sitemap.xml` (generated) MUST list the public paths (`/`, `/about`, `/training`, `/resources`, `/operations`, `/calendar`, `/donations`, `/users/register`) and every **public** operation with a `lastmod`. The sighting page is additionally protected by the `x-robots-tag: noindex, nofollow` response header, and crawler visits never create sightings (§9.1). Absolute URLs everywhere (canonical, OG, sitemap, emails, QR codes) MUST derive from `PHX_HOST` / `MC_EMCOMM_QR_BASE_URL`, never from the request host.

## 27. Notifications & email

Outbound mail goes through Swoosh's Resend adapter from `{"Monroe County ARES/RACES", MAIL_FROM}` (local mailbox adapter in dev, test adapter in test). Account mail: confirmation/login instructions (magic link) and email-change instructions. Membership mail: when a new account confirms and has a pending profile, `Members.notify_new_member_confirmed/1` MUST email the users of approved holders of every `notify_on_new_member` position — deduplicated, one message per recipient so addresses are not shared — with subject "New member awaiting approval: <name>", the member's name, call sign (or "none given"), account email, a link to `/admin/members`, and a line explaining why the recipient received it. Delivery runs under `McEmcomm.TaskSupervisor` so a mail outage can never fail the login that confirmed the account; a later login of an already-confirmed user sends nothing. Inbound: `POST /webhooks/resend` (§24) records the delivery and hands the event to `Inbound.handle_event/1`, a no-op extension point.

## Appendix A — Template baseline

The project was cloned from the `geowa4/base-phoenix` template, which provided: Elixir 1.20 / OTP 28; Bandit; Ecto + PostgreSQL 17; `phx.gen.auth` with magic-link and password authentication using Argon2id; Resend/Swoosh for outbound email plus a signature-verified inbound webhook (its `/inbox` demo LiveView has since been removed); health endpoints and a readiness probe; Prometheus metrics on a private port via PromEx; OpenTelemetry for Phoenix, LiveView, Bandit, and Ecto; JSON logs with trace correlation; the five-layer `mix precommit` gate; Dialyzer in CI; Fly.io blue-green deployment with a release migrator; `AGENTS.md` / `CLAUDE.md` / `GEMINI.md` and `usage_rules` sync; Tidewave MCP in development; `mise.toml`; a self-deleting rename task; the Sprites cloud dev VM tasks; and a default branch of `trunk`.

Template-managed dependency pins, the `precommit` alias steps, `config/runtime.exs` variable names, `fly.toml` health-check/release/blue-green settings, and CI workflow definitions were reconciled with this specification during the Foundation stage and now govern wherever this specification is silent.

## Appendix B — Verified versions & sources

**Certifications.** CISA "Communications Unit Training Resources" and "Communications Unit" pages (COML/COMT/AUXCOMM curriculum, courses + Position Task Books); CISA AUXCOMM PTB PDF; NYS DHSES COMU program.
**Platform.** Fly request-headers doc (`Fly-Client-IP`, `X-Forwarded-For`, `Fly-Region`); `fly mpg create` (`--pg-major-version` 16 or 17, `--enable-postgis-support`); Fly MPG extensions page; ReqS3 hexdocs (`presign_form/1`, `presign_url/1`, `AWS_*` env vars, `allow_upload` external example); eqrcode hexdocs; ua_inspector (databases via `mix ua_inspector.download`, client-hint support, bot detection); nimble_totp; the `aprs` package (Mic-E and compressed decoding); Phoenix 1.8 / LiveView 1.2 (colocated hooks and CSS; `longpoll` option); Leaflet 1.9.4 (last stable 1.x, BSD-2-Clause); `postgis/postgis:17-3.5` and `17-3.6-alpine` Docker Hub tags; adobe/s3mock README (no signature validation, no POST policy conditions); GHSA-628h-q48j-jr6q / CVE-2026-32689 (LiveView long-poll).
**Web platform.** MDN Geolocation API (secure context; coordinates fields); MDN User-Agent Client Hints (`Sec-CH-UA*` low-entropy hints; Safari/Firefox do not implement — keep the raw UA fallback); MDN `<dialog>`/`showModal()`, `<details>`, `popover`, `aria-pressed`, `role="switch"`, `prefers-reduced-motion`; WAI-ARIA Authoring Practices (dialog, disclosure, switch, live regions); OSMF Nominatim Usage Policy and Tile Usage Policy; APRS-IS server-side filter reference (`r/`, `b/` terms; login line format; line length limits of aprsc/javAPRSSrvr).
**Organization.** MonroeCountyEmcomm groups.io (501(c)(3); repeater listings; fourth-Thursday meetings except Jul/Aug/Dec); RARA repeater listing rochesterham.org (146.610/146.010 PL 110.9 W2ARM Cobbs Hill, Monroe County RACES Primary); RepeaterBook ID 36-7183 (Thu 19:00 net); RadioReference Wiki Monroe County (NY) (146.610 N2MPE PL 110.9); monroecountyemcomm.org (former Hugo site, retained locally as content reference). Leadership confirmed on 2026-09-04: the primary repeater is W2ARM (formerly N2MPE) on 146.610 MHz, -0.6 MHz offset, PL 110.9 Hz; the 70 cm repeater is W2ARM on 444.450 MHz, +5 MHz offset, PL 110.9 Hz; the weekly net is Thursday 7:00 PM local; meetings are the fourth Thursday except July, August, and December.

## Appendix C — Test contract: element ids, client events, PubSub

The test suite asserts against these ids; renaming one is a contract change and MUST update the tests.

**Layout**: `#skip-to-content`, `#main-content`, `#nav-home`, `#mobile-nav-home`, `#nav-admin`, `#mobile-nav-admin`, `#mobile-menu`, `#mobile-menu-button`, `#user-menu`, `#user-menu-button`, `#user-menu-portal`, `#user-menu-profile`, `#user-menu-settings`, `#user-menu-log-out`, `#theme-toggle`, `#mobile-theme-toggle`, `#site-footer`, `#header-emblem`, `#header-brand`, `#flash-group`, `#client-error`, `#server-error`.
**Public**: `#leadership-list`, `#position-<id>`, `#weekly-net`, `#repeaters`, `#social-links`, `#drive-folder-link`, `#members-only-note`, `#copy-ics-btn`, `#copy-ics-status`, `#member-operations-link`, `#hero-logo`.
**Auth**: `#registration_form`, `#login_form`, `#login_form_magic`, `#login_form_magic_email`, `#login_form_password`, `#local-mail-notice`, `#confirmation_form`, `#email_form`, `#password_form`, `#settings-two-factor-link`, `#settings-two-factor-status`, `#two-factor-status`, `#two-factor-begin`, `#two-factor-cancel`, `#two-factor-qr`, `#two-factor-secret`, `#two_factor_confirm_form`, `#two-factor-recovery-codes`, `#two-factor-recovery-codes-done`, `#recovery-code-<n>`, `#two-factor-recovery-count`, `#two-factor-regenerate`, `#two-factor-disable`, `#two_factor_form`, `#user_code`, `#two-factor-use-recovery`, `#two-factor-use-totp`, `#two-factor-enabled`, `#two-factor-enrolling`, `#two-factor-disabled`, `#two-factor-back`, `#settings-two-factor`.
**Profile**: `#profile-form`, `#emergency-contact`, `#qth-location`, `#qth-map`, `#qth-map-coordinates`, `#capabilities-section`, `#capability-<id>`, `#capability-name-<id>`, `#capability-description-<id>`, `#courses-section`, `#course-form-<id>`, `#course-completed-on-<id>`, `#certifications-section`, `#certification-form-<id>`, `#certification-issued-on-<id>`.
**Admin**: `#pending-members-section`, `#pending-members`, `#pending-members-<id>`, `#pending-members-empty`, `#members`, `#members-<id>`, `#positions-form-<id>`, `#positions-popover-<id>`, `#emergency-contact-<id>`, `#reason-modal`, `#reason-form`, `#audit-modal`, `#position-modal`, `#position-form`, `#position-row-<id>`, `#positions-rows`, `#positions-reorder-help`, `#move-up-<id>`, `#move-down-<id>`, `#change-holder-<id>`, `#holder-modal`, `#holder-search-form`, `#holder-results`, `#holder-results-region`, `#capability-form`, `#course-form`, `#certification-form`, `#asset-form`, `#document-form`, `#default-location-form`, `#default-location-map`, `#default-location-map-coordinates`, `#default-location-pending-point`, `#operation-form`, `#location-form`, `#location-map`, `#location-map-coordinates`, `#location-pending-point`, `#attachment-form`, `#attachment-description`, `#operations`, `#qr-code`, `#capabilities`, `#courses`, `#certifications`, `#default-locations`, `#documents`.
**Inventory, operations, and sightings**: `#assets`, `#sightings`, `#asset-map`, `#map-filter`, `#map-filter-mode`, `#map-filter-since`, `#operation-map`, `#sighting-client`, `#sighting-form`, `#sighting-submitted`.
**Nets**: `#start-net-form`, `#start-net-aprs-keyword`, `#start-net-operation`, `#checkin-form`, `#checkins`, `#checkin-row-<id>`, `#checkin-aprs-<id>`, `#checkout-checkin-<id>`, `#edit-checkin-<id>`, `#edit-checkin-form`, `#edit-checkin-modal`, `#edit-checkin-location`, `#checkin-location`, `#net-map`, `#net-control`, `#take-net-control`, `#vacate-net-control`, `#change-net-control`, `#ncs-modal`, `#ncs-search-form`, `#ncs-results`, `#ncs-results-region`, `#net-operation`, `#edit-net-operation`, `#net-operation-form`, `#net-operation-select`, `#net-name-form`, `#edit-net-name`, `#net-aprs-keyword`, `#edit-net-aprs-keyword`, `#net-aprs-keyword-form`, `#net-aprs-keyword-input`, `#edit-checkin-call-sign`, `#edit-checkin-notes`.

**Client → server events**: `client_env`, `geolocation`, `geolocation_denied`, `submit` (sighting); `point_selected`, `set_point` / `set_qth_point` (map pickers); `reorder`, `move` (positions); `toggle_capability`, `save_course`, `save_certification` (profile); `check_in`, `check_out`, `update_checkin`, `take_net_control`, `vacate_net_control`, `assign_net_control`, `assign_operation`, `rename_session`, `end_session` (nets); `download` (resources), `download_attachment`, `mark_attendance` (operations). **Server → client events**: `checkin_saved`, `picker:set_point`. **Connect params**: `_csrf_token`, `tz_offset_minutes`.

**PubSub**: see §14.
