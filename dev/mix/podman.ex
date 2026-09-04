defmodule Mix.Podman do
  @moduledoc """
  Shared helpers and container definitions for `mix podman.up` and
  `mix podman.down`, which manage the app's local container dependencies
  (CONTRIBUTING.md § Setup): a PostGIS-enabled Postgres and S3Mock.
  """

  @pg_container "mc-emcomm-pg"
  @pg_volume "mc-emcomm-pgdata"
  @pg_port 5432
  @s3_container "mc-emcomm-s3"
  @s3_port 9090
  @bucket "mc-emcomm-dev"

  def pg_container, do: @pg_container
  def pg_volume, do: @pg_volume
  def pg_port, do: @pg_port
  def s3_container, do: @s3_container
  def s3_port, do: @s3_port
  def bucket, do: @bucket

  def assert_installed! do
    System.find_executable("podman") ||
      Mix.raise("podman is not on PATH; see CONTRIBUTING.md § Setup")

    :ok
  end

  def podman(args), do: System.cmd("podman", args, stderr_to_stdout: true)

  def podman!(args) do
    case podman(args) do
      {out, 0} ->
        String.trim(out)

      {out, code} ->
        Mix.raise("""
        podman #{Enum.join(args, " ")} failed with status #{code}:
        #{String.trim(out)}
        """)
    end
  end

  @doc "Runs podman streaming its output, so image pulls show their progress."
  def stream!(args) do
    {_out, status} = System.cmd("podman", args, into: IO.stream(), stderr_to_stdout: true)

    status == 0 ||
      Mix.raise("podman #{Enum.join(args, " ")} failed with status #{status}")

    :ok
  end

  def container_exists?(name), do: match?({_, 0}, podman(["container", "exists", name]))

  def container_running?(name) do
    case podman(["inspect", "--format", "{{.State.Running}}", name]) do
      {out, 0} -> String.trim(out) == "true"
      _ -> false
    end
  end

  def volume_exists?(name), do: match?({_, 0}, podman(["volume", "exists", name]))

  def step(message), do: Mix.shell().info([:cyan, "==> ", :reset, message])

  def info(message), do: Mix.shell().info("    " <> message)
end
