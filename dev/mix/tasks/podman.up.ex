defmodule Mix.Tasks.Podman.Up do
  @shortdoc "Runs the app's container dependencies (PostGIS and S3Mock) with podman"

  @moduledoc """
  Runs the two podman containers local development depends on, exactly as
  documented in CONTRIBUTING.md § Setup:

    * `mc-emcomm-pg` — PostGIS-enabled PostgreSQL 17
      (`postgres`/`postgres` on `localhost:5432`, matching config's default,
      data in the `mc-emcomm-pgdata` volume). The official image has no
      arm64 build, so it is pinned to `linux/amd64` and runs under emulation
      on Apple Silicon. A host Postgres already on 5432 will make the
      container fail to bind; stop it, or run this container on another port
      by hand and `export PGPORT` (CONTRIBUTING.md § Setup).
    * `mc-emcomm-s3` — S3Mock on `localhost:9090` with the `mc-emcomm-dev`
      bucket pre-created, so presigned uploads round-trip without a real
      bucket.

      mix podman.up

  Each container is created on first run, started if it exists but is
  stopped, and left alone if already running, so the task is safe to re-run.
  It waits for both services to accept connections before returning. Tear
  everything down with `mix podman.down`.
  """
  use Mix.Task

  alias Mix.Podman

  @pg_image "postgis/postgis:17-3.6-alpine"
  @s3_image "adobe/s3mock"
  @attempts 60

  @impl Mix.Task
  def run(_argv) do
    Podman.assert_installed!()

    ensure_container(Podman.pg_container(), pg_run_args())
    ensure_container(Podman.s3_container(), s3_run_args())

    await_postgres()
    await_s3mock()
    summary()
  end

  defp ensure_container(name, run_args) do
    cond do
      Podman.container_running?(name) ->
        Podman.step("Container #{name} is already running")

      Podman.container_exists?(name) ->
        Podman.step("Starting the existing container #{name}")
        Podman.podman!(["start", name])

      true ->
        Podman.step("Creating container #{name}")
        Podman.stream!(["run", "-d", "--name", name | run_args])
    end
  end

  defp pg_run_args do
    [
      "--platform",
      "linux/amd64",
      "-e",
      "POSTGRES_PASSWORD=postgres",
      "-p",
      "#{Podman.pg_port()}:5432",
      "-v",
      "#{Podman.pg_volume()}:/var/lib/postgresql/data",
      @pg_image
    ]
  end

  defp s3_run_args do
    [
      "-p",
      "#{Podman.s3_port()}:9090",
      "-e",
      "COM_ADOBE_TESTING_S3MOCK_STORE_INITIAL_BUCKETS=#{Podman.bucket()}",
      "-t",
      @s3_image
    ]
  end

  defp await_postgres do
    Podman.step("Waiting for Postgres to accept connections")

    # Probe over TCP, not the default unix socket: the image's first-run init
    # runs a temporary server on the socket only, which would pass a socket
    # probe before the real server is up.
    args = [
      "exec",
      Podman.pg_container(),
      "pg_isready",
      "-q",
      "-h",
      "127.0.0.1",
      "-U",
      "postgres"
    ]

    await(
      fn -> match?({_, 0}, Podman.podman(args)) end,
      @attempts,
      "Postgres was not ready after #{@attempts}s; check `podman logs #{Podman.pg_container()}`"
    )
  end

  defp await_s3mock do
    Podman.step("Waiting for S3Mock to accept connections")

    await(
      fn ->
        case :gen_tcp.connect(~c"127.0.0.1", Podman.s3_port(), [:binary, active: false], 1_000) do
          {:ok, socket} ->
            :gen_tcp.close(socket)
            true

          {:error, _reason} ->
            false
        end
      end,
      @attempts,
      "S3Mock was not ready after #{@attempts}s; check `podman logs #{Podman.s3_container()}`"
    )
  end

  defp await(_ready?, 0, message), do: Mix.raise(message)

  defp await(ready?, attempts, message) do
    if ready?.() do
      :ok
    else
      Process.sleep(1_000)
      await(ready?, attempts - 1, message)
    end
  end

  defp summary do
    Mix.shell().info("""

    Local dependencies are running.

      Postgres: localhost:#{Podman.pg_port()} (postgres/postgres)
      S3Mock:   localhost:#{Podman.s3_port()} (bucket #{Podman.bucket()})

    Uploads round-trip when the server runs with:

      AWS_ACCESS_KEY_ID=test AWS_SECRET_ACCESS_KEY=test AWS_REGION=us-east-1 \\
        AWS_ENDPOINT_URL_S3=http://localhost:#{Podman.s3_port()} BUCKET_NAME=#{Podman.bucket()} \\
        mix phx.server

    Tear down with `mix podman.down`.
    """)
  end
end
