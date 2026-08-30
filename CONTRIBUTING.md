# CONTRIBUTING.md

Contributor reference for humans and coding agents. The always-loaded agent rules
live in AGENTS.md; this file holds the detail those rules point to.

## Setup

- Toolchain: Erlang/OTP 28 and Elixir 1.20 (pinned in `mise.toml`; `mise install`).
  PostgreSQL 17 on `localhost:5432` with `postgres`/`postgres`
  (for example `podman run -d --name base-phoenix-pg -e POSTGRES_PASSWORD=postgres
  -p 5432:5432 -v base-phoenix-pgdata:/var/lib/postgresql/data postgres:17`).
- Install and set up everything: `mix setup`
- Create/migrate/seed the database: `mix ecto.setup`
- Drop and recreate the database: `mix ecto.reset`
- Run the app: `mix phx.server` (or `iex -S mix phx.server`)
- Quality gate: `mix precommit` (steps defined by the alias in `mix.exs`).
  Dialyzer runs in CI; run `mix dialyzer` locally only when investigating a
  CI failure.
- Pre-commit hook (format + credo): `git config core.hooksPath .githooks`
- Catch up with origin: `mix sync` fetches and rebases the current branch onto
  origin's default branch (in `dev/`, dev/test only). A conflicting rebase is
  left in progress for you to resolve and the task fails. `mix sprite.sync`
  does the same inside the app's sprite.
- Agent instruction sync: `mix usage_rules.sync` after every dependency change;
  `mix usage_rules.sync --check` reports drift without writing.
- Tidewave MCP for coding agents (dev only): `claude mcp add --transport http tidewave http://127.0.0.1:4000/tidewave/mcp`

## Testing

- Run all tests: `mix test`
- Run one file: `mix test test/my_app_web/live/inbox_live_test.exs`
- Run one test: `mix test test/my_app_web/live/inbox_live_test.exs:42`
- Re-run only failures: `mix test --failed`
- Coverage report: `mix test --cover` (CI enforces the threshold set in `mix.exs`)
- Stack: ExUnit, Ecto SQL Sandbox, Mox, StreamData, `Phoenix.LiveViewTest`,
  PhoenixTest. `Req.Test` stubs the HTTP behind `MyApp.Resend` (see
  `config/test.exs`); consumers of the Receiving API depend on the
  `MyApp.Resend.Client` behaviour and are tested against `MyApp.ResendMock`
  (Mox, defined in `test/support/mocks.ex`, wired via `:resend_client`).

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
  is an opt-in for teams that need it (`config :my_app, MyApp.Repo, migration_lock: :pg_advisory_lock`).
- Migrations run in prod via `MyApp.Release.migrate/0` (the Fly release command),
  never `mix ecto.migrate` on a prod box.

## Inbound webhooks

- Resend `email.received` events are metadata-only; full content, when needed, is
  fetched from the Receiving API using the event's email id.
- Signatures are verified manually with the Svix scheme: HMAC-SHA256 over
  `id.timestamp.body`, `whsec_`-stripped base64-decoded key, constant-time
  comparison, ±300s timestamp tolerance. The absence of a `svix` dependency is
  a deliberate decision — do not add one.
- Events are deduplicated on `svix-id` via the `webhook_events` table; handlers
  return 200 fast. Only the `svix-id` (and event type) is persisted — email
  metadata is never stored in the database.
- After dedupe, `MyApp.Inbound` broadcasts the event metadata over
  `Phoenix.PubSub` on a per-sender topic (`inbound_emails:<normalized from>`).
  The `/inbox` LiveView subscribes for the logged-in user's address, backfills
  history from `GET /emails/receiving`, and keeps everything in process memory.
- `From`-based matching is spoofable; it demonstrates data flow and must never
  be used as an authentication or authorization signal.
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

- Fly.io, blue-green (`fly.toml`), migrations via the release command.
- Secrets (`fly secrets set ...`): `SECRET_KEY_BASE`, `DATABASE_URL`,
  `RESEND_API_KEY`, `RESEND_WEBHOOK_SECRET`, `MAIL_FROM` (sender for account
  emails; must be on a domain verified in Resend), and optionally
  `OTEL_EXPORTER_OTLP_ENDPOINT` / `OTEL_EXPORTER_OTLP_HEADERS`.
- `min_machines_running = 1` is mandatory: `auto_stop_machines` would otherwise
  stop the background GenServers (health probe, PromEx, schedulers).

### First deploy

Fly app names cannot contain underscores, so `fly.toml` uses the kebab-case
form of the app name (`app` and `PHX_HOST`); `mix my_app.rename` rewrites both.

```sh
fly apps create <app> --org <org>

# Database: use Managed Postgres (`fly mpg`) for anything real. It provides
# backups, point-in-time restore, and HA plans. Note that MPG currently offers
# Postgres 16/17 (the app runs 18 locally; nothing here depends on 18-only
# features).
fly mpg create --name <app>-db --org <org> --region iad --pg-major-version 17 --plan basic
fly mpg attach <cluster-id> --app <app>      # sets DATABASE_URL
# Both mpg commands print the full connection string, password included, to
# the terminal. Treat scrollback, CI logs, and agent transcripts as tainted;
# see "Rotating the database credential" below.

# Secrets. Stage them so they ship with the first deploy instead of triggering
# a release each.
fly secrets set --app <app> --stage \
  SECRET_KEY_BASE="$(mix phx.gen.secret)" \
  RESEND_API_KEY="re_..." \
  RESEND_WEBHOOK_SECRET="whsec_..." \
  MAIL_FROM="noreply@<verified-domain>"

# GIT_SHA is baked into the image; the remote builder never sees .git, so it
# must be passed explicitly (the deploy workflow does this for you).
fly deploy --remote-only --build-arg GIT_SHA="$(git rev-parse HEAD)"
curl https://<app>.fly.dev/healthz/ready     # => ready
curl https://<app>.fly.dev/healthz/version   # => {"version":"<sha>"}
fly checks list --app <app>                # live + readiness passing per machine
```

`fly postgres create` (unmanaged, "Fly Postgres") is acceptable for throwaway
testing only: it is a plain Postgres VM with no backups or managed failover.
Give it at least 512 MB (`--vm-size shared-cpu-1x` defaults to 256 MB, which
the OOM killer takes down within minutes: postgres-flex runs postgres, repmgr,
haproxy, and an exporter). Attach it with
`fly postgres attach <db-app> --app <app>`; the app config is identical either
way because it only consumes `DATABASE_URL`.

The template repository itself is deployed as the reference instance
`base-phoenix` without renaming, by overriding the placeholders at deploy time:
`fly secrets set --app base-phoenix PHX_HOST=base-phoenix.fly.dev` once, then
`fly deploy --remote-only -a base-phoenix --build-arg GIT_SHA="$(git rev-parse HEAD)"`
(secrets take precedence over `[env]`).

### Continuous deployment

`.github/workflows/deploy.yml` deploys every successful CI run on the default
branch, and can also be run by hand from the Actions tab (that deploys the ref
you select). It is inert until the repository is configured, so a fresh copy of
the template does nothing on push:

- Repository variable `FLY_APP`: the Fly app name. The job is skipped while it
  is unset.
- Repository secret `FLY_API_TOKEN`: a deploy token scoped to that one app. The
  job fails with an explicit error if `FLY_APP` is set but the token is missing.

The workflow reads the app name from the variable rather than from `fly.toml`,
so `mix my_app.rename` does not touch it and the template itself can deploy its
reference instance without renaming.

```sh
gh variable set FLY_APP --body <app>

# Deploy tokens are limited to one app. The default expiry is 20 years; prefer
# something shorter and rotate. Piping into gh keeps the token out of your
# scrollback.
fly tokens create deploy --app <app> --name github-actions --expiry 8760h \
  | gh secret set FLY_API_TOKEN
```

To rotate, run the same `fly tokens create ... | gh secret set` pipeline (it
replaces the secret), then revoke the old token: `fly tokens list --scope app
--app <app>` and `fly tokens revoke <id>`.

The deploy job runs in the `production` environment. Restrict that environment
to the default branch so a manual run from the Actions tab cannot deploy an
arbitrary ref: automatic deploys are already limited to pushes on the default
branch by the workflow itself, but `workflow_dispatch` accepts any ref the
person triggering it selects. The policy is a repository setting, not part of
the workflow file, so each repository created from the template sets it once
(replace `trunk` with your default branch). This is a custom branch policy
rather than "protected branches only" because branch protection is not
available on private repositories on the free plan.

```sh
gh api -X PUT repos/{owner}/{repo}/environments/production \
  --input - <<'JSON'
{"deployment_branch_policy":{"protected_branches":false,"custom_branch_policies":true}}
JSON
gh api -X POST repos/{owner}/{repo}/environments/production/deployment-branch-policies \
  -f name=trunk -f type=branch
```

The equivalent UI path is Settings → Environments → production → Deployment
branches and tags → Selected branches and tags. No reviewer is required: the
gate is "what can be deployed", not "who approves it".

### Rotating the database credential

The connection string is an ordinary Fly secret: `fly mpg create`/`attach`
print it, and `fly ssh console -C 'sh -c "printenv DATABASE_URL"'` reads it
back from any machine. Rotation is zero-downtime if done in this order:

```sh
fly mpg users create <cluster-id> --username <new-user> --role schema_admin
fly mpg attach <cluster-id> --app <app> --username <new-user>   # rewrites DATABASE_URL
fly status --app <app>        # wait until only the new machine version remains
fly mpg users delete <cluster-id> --username <old-user>
```

- The role **must** be `schema_admin`. MPG tables are owned by the shared
  `schema_admin` role rather than by the user that created them, so a new
  `schema_admin` user inherits ownership and migrations keep working; a
  `writer` user can read and write but every `ALTER TABLE` and the migrator's
  lock on `schema_migrations` will fail.
- `attach` sets `DATABASE_URL` as an unstaged secret, which rolls the machines:
  new ones pass the readiness gate on the new credential before old ones stop.
- Deleting a user kills its live connections immediately. Delete the old user
  only after the old machines are gone, never before re-attaching — otherwise
  the pool cannot reconnect, `/healthz/ready` fails, and Fly stops routing to
  the app until a new secret is deployed.

After the first deploy, point the Resend `email.received` webhook at
`https://<app>.fly.dev/webhooks/resend` and set `RESEND_WEBHOOK_SECRET` to the
signing secret Resend shows for that endpoint.

## Sprites (cloud dev VM)

A [Fly.io Sprite](https://sprites.dev) is a small Linux VM with Claude Code
preinstalled. The `mix sprite.*` tasks (in `dev/`, compiled only in dev/test)
provision one as a complete copy of this development environment via the
[sprites-ex](https://github.com/superfly/sprites-ex) SDK.

- Prerequisites: the `sprite` CLI, logged in (for `mix sprite.connect`), and an
  API token from https://sprites.dev/account exported as `SPRITES_TOKEN`. The
  CLI's own token is stored encrypted, so the SDK cannot reuse it.
- Create and provision: `mix sprite.up [--name NAME] [--ssh-key PATH]`.
  It creates the sprite (default name: the repository name), installs PostgreSQL
  and runs it as the `postgres` service (`postgres`/`postgres` on `localhost:5432`),
  installs the Elixir pinned in `mise.toml`, generates a key pair in the
  sprite and registers it as a write-enabled deploy key on the GitHub repo with
  `gh` (or copies `--ssh-key PATH`; required for non-GitHub remotes), copies
  your git identity, clones the current branch into `/home/sprite/<repo>`, runs
  `mix setup`, runs `mix phx.server` as the `phoenix` service routed to the
  sprite's URL, and takes a checkpoint of the running app. Every step is
  idempotent; re-run it to resume after a failure or to restart the services
  (a checkpoint is only taken when none with the same comment exists yet).
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
- Known differences from local: the sprite image ships Ubuntu 26.04, so its
  packaged PostgreSQL is 18 (Fly Managed Postgres is 17; nothing here depends on
  18-only features), and the sprite's Erlang/OTP 28.x build is used rather than
  the exact patch pinned in `mise.toml`. The sprite's URL is reachable by
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
