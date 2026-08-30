# MyApp — Elixir + Phoenix starter template

A batteries-included, production-shaped Phoenix 1.8 LiveView application:

- Elixir 1.20 / OTP 28, Bandit, Ecto + PostgreSQL 17
- `phx.gen.auth` (magic link + password, Argon2id)
- Resend outbound email (Swoosh) and a signature-verified inbound webhook
  feeding an authenticated `/inbox` LiveView over PubSub
- Health endpoints, Prometheus on a private port, OpenTelemetry, JSON logs
- Five-layer quality gate under `mix precommit`; Dialyzer in CI
- Fly.io blue-green deployment with a release migrator
- First-class coding-agent support: `AGENTS.md` (canonical), `CLAUDE.md` bridge,
  usage_rules sync, Tidewave MCP in dev

## Create a project

1. Use this repository as a GitHub template and clone it.
2. Rename the placeholders (run once; the task deletes itself):

       mix my_app.rename --otp my_shop --module MyShop

3. Update the copyright line in `LICENSE`.
4. Bootstrap:

       mix setup
       mix usage_rules.sync
       mix precommit
       mix phx.server

See `CONTRIBUTING.md` for setup, testing, migrations, webhooks, observability
and deployment, and `AGENTS.md` for the rules coding agents follow.

## Bootstrap checklist

- [ ] `mix my_app.rename` run; template task self-deleted.
- [ ] `LICENSE` copyright line updated.
- [ ] `mix setup` completes; `mix phx.server` boots.
- [ ] `mix precommit` passes locally.
- [ ] `mix usage_rules.sync` run; AGENTS.md managed section committed.
- [ ] Inbox smoke test: an email from a registered address appears live at `/inbox`
      and survives a remount via API backfill.
- [ ] Fly secrets set; blue-green deploy succeeds; readiness gate healthy.
- [ ] `README.md` rewritten to describe this project (template intro and this
      checklist removed).
