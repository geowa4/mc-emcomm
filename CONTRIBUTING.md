# CONTRIBUTING.md

Contributor reference for humans and coding agents. The always-loaded agent rules
live in AGENTS.md; this file holds the detail those rules point to.

## Setup

- Toolchain: Erlang/OTP 28 and Elixir 1.20 (pinned in `mise.toml`; `mise install`).
  PostGIS-enabled PostgreSQL 17 with `postgres`/`postgres` — plain Postgres will
  not run this app (the first migration creates the `postgis` extension).
  `mix podman.up` runs it with podman on `localhost:5432` (config's default)
  along with S3Mock for uploads; the official image has no arm64 build, so
  the task pins `--platform linux/amd64` (README § Local setup has the raw
  commands, and `PGPORT` covers a non-default port).
  `mix podman.down` removes both containers and the `mc-emcomm-pgdata`
  volume, deleting the local database.
- Install and set up everything: `mix setup`
- Run everything for local dev in one command: `mix dev.server` — containers
  (`mix podman.up`), create/migrate/seed, `ua_inspector` databases, then
  `mix phx.server` with the S3Mock storage environment defaulted (already
  exported variables win).
- Create/migrate/seed the database: `mix ecto.setup`
- Drop and recreate the database: `mix ecto.reset`
- Run the app: `mix phx.server` (or `iex -S mix phx.server`)
- Quality gate: `mix precommit` (steps defined by the alias in `mix.exs`).
  Dialyzer runs in CI and in `mix prepush`; run `mix dialyzer` on its own only
  when investigating a CI failure.
- Full CI mirror: `mix prepush` runs everything CI runs — `precommit` plus the
  dependency audits, sobelow, the drift guards, coverage, and dialyzer (steps
  defined by the alias in `mix.exs`; keep it in sync with
  `.github/workflows/ci.yml`).
- Git hooks (pre-commit: format + credo; pre-push: `mix prepush`):
  `git config core.hooksPath .githooks`
- Catch up with origin: `mix sync` fetches and rebases the current branch onto
  origin's default branch (in `dev/`, dev/test only). A conflicting rebase is
  left in progress for you to resolve and the task fails. `mix sprite.sync`
  does the same inside the app's sprite.
- Agent instruction sync: `mix usage_rules.sync` after every dependency change;
  `mix usage_rules.sync --check` reports drift without writing.
- Tidewave MCP for coding agents (dev only): `claude mcp add --transport http tidewave http://127.0.0.1:4000/tidewave/mcp`

## Testing

- Run all tests: `mix test`
- Run one file: `mix test test/mc_emcomm_web/controllers/webhook_controller_test.exs`
- Run one test: `mix test test/mc_emcomm_web/controllers/webhook_controller_test.exs:42`
- Re-run only failures: `mix test --failed`
- Coverage report: `mix test --cover` (CI enforces the threshold set in `mix.exs`)
- Stack: ExUnit, Ecto SQL Sandbox, Mox, StreamData, `Phoenix.LiveViewTest`,
  PhoenixTest. External HTTP dependencies are stubbed behind behaviours with
  Mox mocks (defined in `test/support/mocks.ex`).

## Database & migrations

- Blue-green deployment runs old and new code against one database. Use
  expand-contract: ship an additive migration, roll out code, then ship a
  contracting migration later. Never change schema and dependent code in one step.
- Create indexes concurrently outside a transaction:
  `@disable_ddl_transaction true` and `@disable_migration_lock true`.
- Add CHECK constraints with `NOT VALID` first, then `VALIDATE CONSTRAINT` in a
  later migration.
- Set `lock_timeout` / `statement_timeout` for potentially slow DDL.
- The Ecto `migration_lock` default (`:table_lock`) is kept; `:pg_advisory_lock`
  is an opt-in for teams that need it (`config :mc_emcomm, McEmcomm.Repo, migration_lock: :pg_advisory_lock`).
- Migrations run in prod via `McEmcomm.Release.migrate/0` (the Fly release command),
  never `mix ecto.migrate` on a prod box.

## Inbound webhooks

- Resend `email.received` events are metadata-only; full content, when needed,
  can be fetched from the Receiving API using the event's email id.
- Signatures are verified manually with the Svix scheme: HMAC-SHA256 over
  `id.timestamp.body`, `whsec_`-stripped base64-decoded key, constant-time
  comparison, ±300s timestamp tolerance. The absence of a `svix` dependency is
  a deliberate decision — do not add one.
- Events are deduplicated on `svix-id` via the `webhook_events` table; handlers
  return 200 fast. Only the `svix-id` (and event type) is persisted — email
  metadata is never stored in the database.
- After dedupe, events are dispatched asynchronously to
  `McEmcomm.Inbound.handle_event/1`, currently a no-op extension point for
  future processing.
- Endpoint: `POST /webhooks/resend`. Point the Resend webhook at
  `https://<host>/webhooks/resend` and set `RESEND_WEBHOOK_SECRET`.

## Observability & health

- `GET /healthz/live` — liveness, always 200, dependency-free.
- `GET /healthz/ready` — readiness from a periodic `SELECT 1` probe cached in
  `:persistent_term`.
- `GET /healthz/version` — `{"version": "<git sha>"}` of the deployed build,
  from the `GIT_SHA` build arg (`unknown` when not passed, e.g. locally). The
  same value is the OpenTelemetry `service.version` resource attribute.
- Prometheus metrics are served on private port 9091 (`METRICS_PORT`) and
  scraped by Fly; the port is never exposed as a public service.
- OpenTelemetry is wired for Phoenix (incl. LiveView), Bandit, and Ecto;
  `trace_id`/`span_id` appear in the JSON logs. Tracing exports over OTLP when
  `OTEL_EXPORTER_OTLP_ENDPOINT` is set.
- LiveDashboard: `/dev/dashboard` (requires login). Mailbox preview (dev): `/dev/mailbox`.

## Deployment

Standing up and operating a production instance is documented in DEPLOY.md
(first deploy, custom domain, continuous deployment, and the runbook for
promoting the first administrator, resetting two-factor authentication, and
rotating the database credential). What a contributor needs to know:

- Fly.io, blue-green (`fly.toml`), migrations via the release command. Blue
  and green run side by side during a deploy, which is why "Database &
  migrations" above requires expand-contract.
- Runtime configuration is read from environment variables in
  `config/runtime.exs`. Secrets (`fly secrets set ...`): `SECRET_KEY_BASE`,
  `DATABASE_URL`, `RESEND_API_KEY`, `RESEND_WEBHOOK_SECRET`, `MAIL_FROM`
  (sender for account emails; must be on a domain verified in Resend), and
  optionally `OTEL_EXPORTER_OTLP_ENDPOINT` / `OTEL_EXPORTER_OTLP_HEADERS`.
  `PHX_HOST` and `MC_EMCOMM_QR_BASE_URL` name the public origin; anything
  that builds an absolute URL (emails, canonical links, the sitemap, QR
  codes) must derive from them rather than from the request.
- `min_machines_running = 1` is mandatory: `auto_stop_machines` would otherwise
  stop the background GenServers (health probe, PromEx, schedulers).
- Every successful CI run on the default branch deploys through
  `.github/workflows/deploy.yml`; merging to trunk ships. Configuring the
  workflow is covered in DEPLOY.md § Continuous deployment.
- Operator commands live in `McEmcomm.Release` and run from the release with
  `fly ssh console -C "/app/bin/mc_emcomm eval '...'"`; add new ones there.

## Sprites (cloud dev VM)

A [Fly.io Sprite](https://sprites.dev) is a small Linux VM with Claude Code
preinstalled. The `mix sprite.*` tasks (in `dev/`, compiled only in dev/test)
provision one as a complete copy of this development environment via the
[sprites-ex](https://github.com/superfly/sprites-ex) SDK.

- Prerequisites: the `sprite` CLI, logged in (for `mix sprite.connect`), and an
  API token from https://sprites.dev/account exported as `SPRITES_TOKEN`. The
  CLI's own token is stored encrypted, so the SDK cannot reuse it.
- Create and provision: `mix sprite.up [--name NAME] [--ssh-key PATH]`.
  It creates the sprite (default name: the repository name), installs
  PostgreSQL 17 with PostGIS from the PGDG apt repository (the major Fly
  Managed Postgres runs, matching CI and local dev; the first migration's
  `CREATE EXTENSION postgis` needs the extension packages) and runs it as the
  `postgres` service (`postgres`/`postgres` on `localhost:5432`), downloads
  the checksum-pinned S3Mock standalone jar — the same app as the
  `adobe/s3mock` container in README § Setup — and runs it as the `s3mock`
  service on `localhost:9090` with a persistent store under
  `~/.local/share/s3mock`, installs the Elixir pinned in `mise.toml`,
  generates a key pair in the sprite and registers it as a write-enabled
  deploy key on the GitHub repo with `gh` (or copies `--ssh-key PATH`;
  required for non-GitHub remotes), copies your git identity, clones the
  current branch into `/home/sprite/<repo>`, runs `mix setup`, runs
  `mix phx.server` as the `phoenix` service routed to the sprite's URL — with
  `AWS_*`/`BUCKET_NAME` pointed at S3Mock so presigned uploads round-trip —
  and takes a checkpoint of the running app. Every step is idempotent; re-run
  it to resume after a failure or to restart the services (a checkpoint is
  only taken when none with the same comment exists yet). Services are only
  created, never redefined: a sprite provisioned before the `s3mock` service
  existed keeps its old `phoenix` definition until you
  `sprite-env services delete phoenix` from a console and re-run
  `mix sprite.up` (or recreate the sprite).
- Open a session: `mix sprite.connect` starts a login shell in the repository
  directory; `mix sprite.connect -- claude` (or any command) runs that instead.
  It hands the terminal to `sprite exec --tty`, so Ctrl-\ detaches and
  `sprite sessions` / `sprite attach` manage sessions. When the session ends
  the task offers to take a checkpoint (`--no-checkpoint` to skip).
- Claude Code is preinstalled but not signed in: `mix sprite.connect -- claude`,
  then `/login`. Take a checkpoint afterwards if you want to keep it.
- Update to the latest code: `mix sprite.sync [--no-checkpoint]` fetches
  `origin`, rebases the sprite's checked-out branch onto origin's default branch
  (a conflicting rebase is aborted and the task fails; the working tree must be
  clean), and when the `phoenix` service is running restarts it after
  `mix deps.get`, `mix assets.setup`, `mix compile`, and `mix ecto.migrate`,
  waiting for `/healthz/ready`. It then takes a checkpoint named after the new
  commit. Nothing happens when the sprite is already up to date.
- Stop the services: `mix sprite.stop` (the sprite pauses on its own when idle).
- Destroy it: `mix sprite.down [--yes]` deletes the sprite with its checkpoints
  and removes its deploy key from the GitHub repository.
- Checkpoints: `mix sprite.checkpoint create [--comment TEXT]`,
  `mix sprite.checkpoint list`, `mix sprite.checkpoint restore ID`. Checkpoints
  capture the filesystem only; restoring restarts the environment and brings the
  services back from their definitions.
- Known differences from local: PostgreSQL 17 and PostGIS come from PGDG apt
  packages rather than the `postgis/postgis:17-3.6` container (same majors),
  and the sprite's Erlang/OTP 28.x build is used rather than the exact patch
  pinned in `mise.toml`. S3Mock runs as the standalone jar behind the
  `adobe/s3mock` image — its known local limits (no signature validation, no
  POST policy enforcement) apply in the sprite too, but its store is
  persistent instead of tmpdir-backed. Containers themselves don't work in a
  sprite (verified empirically): rootless podman is blocked from `/dev/fuse`
  and `/dev/net/tun`, and rootful podman fails intermittently on cgroup
  controller delegation. The sprite's URL is reachable by
  org members only until `sprite url update --auth public -s NAME`. A copied
  `--ssh-key` must not have a passphrase (nothing can enter it in the sprite).
  Destroying a sprite any other way than `mix sprite.down` leaves its deploy
  key on GitHub.
- Inspect services and logs from a console: `sprite-env services list`,
  `tail -f /.sprite/logs/services/phoenix.log`.

## Add-ons (documented, not installed)

- **Assent** (`~> 0.3`) — OAuth/OIDC. Add a `user_identities` table keyed on
  `user_id + provider + uid` with a unique index on `{provider, uid}`; configure
  providers from environment variables.
- **Cachex** (`4.1.x`) — add when a real caching need appears.
- **logger_json** — other formatters (`GoogleCloud`, `Datadog`, `Elastic`) for
  non-Fly log sinks.
- Community agent skills/plugins (`claude-code-elixir`, `claude-elixir-phoenix`,
  `bmad-elixir`, HexDocs MCP, ElixirLS MCP) are references only; skills are
  executable instructions — review before adopting.
