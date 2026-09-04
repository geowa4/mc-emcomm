defmodule Mix.Tasks.Dev.Server do
  @shortdoc "Runs everything for local development in one command"

  @moduledoc """
  Brings up a complete local environment and runs the server:

    1. `mix podman.up` — the PostGIS Postgres and S3Mock containers
    2. defaults the S3Mock storage environment (`AWS_*`, `BUCKET_NAME`;
       CONTRIBUTING.md § Setup) for any variable not already exported, so
       presigned uploads round-trip — set them yourself first to point at a
       real bucket instead
    3. `mix ecto.create` + `mix ecto.migrate`
    4. `mix ua_inspector.download` when the parser databases are missing, so
       boot does not log "Failed to load database"
    5. `mix phx.server`
    6. seeds the database (`priv/repo/seeds.exs`, idempotent) once the app
       is up

      mix dev.server

  Every step is idempotent, so this is the normal way to start the day.
  Run `mix setup` once after cloning (or after dependency changes) first —
  this task assumes deps and the asset toolchain are installed.
  """
  use Mix.Task

  alias Mix.Podman

  @impl Mix.Task
  def run(_argv) do
    Mix.Task.run("podman.up")

    # Before anything evaluates config/runtime.exs, which mirrors
    # AWS_ENDPOINT_URL_S3 into the Content-Security-Policy.
    put_s3mock_env_defaults()

    Mix.Task.run("ecto.create")
    Mix.Task.run("ecto.migrate")

    download_ua_databases()

    # Returns once the app is serving; --no-halt keeps the VM alive.
    Mix.Task.run("phx.server")

    Podman.step("Seeding the database")
    Code.eval_file("priv/repo/seeds.exs")
  end

  defp put_s3mock_env_defaults do
    defaults = %{
      "AWS_ACCESS_KEY_ID" => "s3mock",
      "AWS_SECRET_ACCESS_KEY" => "s3mock",
      "AWS_REGION" => "us-east-1",
      "AWS_ENDPOINT_URL_S3" => "http://localhost:#{Podman.s3_port()}",
      "BUCKET_NAME" => Podman.bucket()
    }

    missing = Enum.reject(defaults, fn {name, _value} -> System.get_env(name) end)

    unless missing == [] do
      Podman.step("Defaulting #{Enum.map_join(missing, ", ", &elem(&1, 0))} to S3Mock")
      System.put_env(missing)
    end
  end

  # The databases load into ETS when the :ua_inspector app starts, so they
  # must exist before phx.server boots the app.
  defp download_ua_databases do
    Mix.Task.run("loadpaths")
    priv = Application.app_dir(:ua_inspector, "priv")

    if Path.wildcard(Path.join(priv, "*.yml")) == [] do
      Podman.step("Downloading the ua_inspector databases (first run only)")
      Mix.Task.run("ua_inspector.download", ["--force"])
    end
  end
end
