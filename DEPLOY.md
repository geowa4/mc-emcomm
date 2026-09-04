# DEPLOY.md

Operator reference: how to stand up, configure, and look after a production
instance of this application on Fly.io. Nothing here is needed to contribute
code; that reference is CONTRIBUTING.md, whose Deployment section lists the
environment variables and the blue-green constraints the code must respect.

## Deploying

- Fly.io, blue-green (`fly.toml`), migrations via the release command
  (`McEmcomm.Release.migrate/0`).
- Secrets (`fly secrets set ...`): `SECRET_KEY_BASE`, `DATABASE_URL`,
  `RESEND_API_KEY`, `RESEND_WEBHOOK_SECRET`, `MAIL_FROM` (sender for account
  emails; must be on a domain verified in Resend), and optionally
  `OTEL_EXPORTER_OTLP_ENDPOINT` / `OTEL_EXPORTER_OTLP_HEADERS`. The
  application-specific variables (`MC_EMCOMM_*`, the Tigris bucket) are
  tabulated in CONTRIBUTING.md § Configuration.
- `min_machines_running = 1` is mandatory: `auto_stop_machines` would otherwise
  stop the background GenServers (health probe, PromEx, schedulers).

### First deploy

Fly app names cannot contain underscores, so `fly.toml` uses the kebab-case
form of the app name (`app` and `PHX_HOST`); `mix mc_emcomm.rename` rewrites both.

```sh
fly apps create <app> --org <org>

# Database: use Managed Postgres (`fly mpg`) for anything real. It provides
# backups, point-in-time restore, and HA plans. Note that MPG currently offers
# Postgres 16/17 (the app runs 18 locally; nothing here depends on 18-only
# features).
# PostGIS is required (asset locations and sighting points are geometry
# columns); fall back to --pg-major-version 16 if PG17+PostGIS is not offered
# in the target region.
fly mpg create --name <app>-db --org <org> --region iad --pg-major-version 17 --plan basic \
  --enable-postgis-support
fly mpg attach <cluster-id> --app <app>      # sets DATABASE_URL
# Both mpg commands print the full connection string, password included, to
# the terminal. Treat scrollback, CI logs, and agent transcripts as tainted;
# see "Rotating the database credential" below.

# Uploads go in a private Tigris bucket. This sets BUCKET_NAME and the AWS_*
# credentials as secrets on the app.
fly storage create --name <app>-uploads --org <org> --app <app>

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

After the first deploy, point the Resend `email.received` webhook at
`https://<app>.fly.dev/webhooks/resend` and set `RESEND_WEBHOOK_SECRET` to the
signing secret Resend shows for that endpoint.

### Custom domain

`fly.toml` sets `PHX_HOST` to the Fly subdomain, and several things are built
from that value at runtime: the links in account emails, the canonical and
Open Graph URLs on every page, and `sitemap.xml`. Serving the site at its own
domain without updating it points search engines and link previews at the Fly
subdomain instead. Sighting QR codes encode `MC_EMCOMM_QR_BASE_URL`, which is
read separately, so set both to the same origin.

```sh
fly certs add --app <app> monroecountyemcomm.org
fly certs add --app <app> www.monroecountyemcomm.org
fly certs show --app <app> monroecountyemcomm.org   # prints the DNS records to create

# Secrets take precedence over [env] in fly.toml, so no file change is needed.
fly secrets set --app <app> \
  PHX_HOST=monroecountyemcomm.org \
  MC_EMCOMM_QR_BASE_URL=https://monroecountyemcomm.org
```

Create the A/AAAA (or CNAME) and the `_acme-challenge` records `fly certs show`
lists, then wait for `fly certs check` to report the certificate issued.
Verify with `curl -sI https://monroecountyemcomm.org/about | grep -i canonical`
after the machines have rolled: the `<link rel="canonical">` and
`robots.txt`'s `Sitemap:` line should both name the new host. QR codes printed
before the change still work only if the old host keeps resolving, so leave
the Fly subdomain in place or reprint them.

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
so `mix mc_emcomm.rename` does not touch it and the template itself can deploy its
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

## Runbook

### First administrator

Nothing in the deploy path seeds an admin: migrations only create schema, and
`priv/repo/seeds.exs` is dev-only. On a fresh database, register an account
through the site as usual, then grant it the admin flag from the release:

```sh
fly ssh console --app <app> -C "/app/bin/mc_emcomm eval 'McEmcomm.Release.promote_admin(\"you@example.org\")'"
```

The call is idempotent and does not require a member profile; the admin
console works with the flag alone. Member-only actions (running a net, marking
attendance, holding a position) still need an approved member profile, which
the admin can create and approve like anyone else's.

### Resetting two-factor authentication

Users can turn on TOTP two-factor authentication under Account → Manage
two-factor authentication, and receive eight single-use recovery codes when
they do. A member who has lost both their authenticator and every recovery
code cannot log in; verify who you are talking to out of band, then clear
their second factor from the release:

```sh
fly ssh console --app <app> -C "/app/bin/mc_emcomm eval 'McEmcomm.Release.disable_totp(\"you@example.org\")'"
```

The call is idempotent. It forgets the TOTP secret and deletes the recovery
codes but leaves existing sessions alone; the member logs in with their
password or a magic link and can re-enroll from settings.

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
