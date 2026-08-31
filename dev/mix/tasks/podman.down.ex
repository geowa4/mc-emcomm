defmodule Mix.Tasks.Podman.Down do
  @shortdoc "Removes the podman dependency containers as if they were never created"

  @moduledoc """
  Tears down everything `mix podman.up` created: removes the `mc-emcomm-pg`
  and `mc-emcomm-s3` containers (running or not) and the `mc-emcomm-pgdata`
  volume — which DELETES the local database. S3Mock keeps its objects in the
  container's tmpdir, so they disappear with the container.

      mix podman.down

  The pulled images are kept so the next `mix podman.up` is fast; remove
  them with `podman rmi` if you want the disk space back.
  """
  use Mix.Task

  alias Mix.Podman

  @impl Mix.Task
  def run(_argv) do
    Podman.assert_installed!()

    Enum.each([Podman.pg_container(), Podman.s3_container()], &remove_container/1)
    remove_volume(Podman.pg_volume())
  end

  defp remove_container(name) do
    if Podman.container_exists?(name) do
      Podman.step("Removing container #{name}")
      Podman.podman!(["rm", "--force", "--volumes", "--time", "5", name])
    else
      Podman.info("Container #{name} does not exist")
    end
  end

  defp remove_volume(name) do
    if Podman.volume_exists?(name) do
      Podman.step("Removing volume #{name}")
      Podman.podman!(["volume", "rm", name])
    else
      Podman.info("Volume #{name} does not exist")
    end
  end
end
