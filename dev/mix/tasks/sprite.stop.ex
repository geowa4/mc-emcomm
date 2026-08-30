defmodule Mix.Tasks.Sprite.Stop do
  @shortdoc "Stops the Phoenix and PostgreSQL services in the app's Sprite"

  @moduledoc """
  Stops the `phoenix` and `postgres` services created by `mix sprite.up`. The
  sprite itself keeps existing (and pauses on its own once idle); re-run
  `mix sprite.up` to start the services again.

      mix sprite.stop [--name NAME]
  """
  use Mix.Task

  alias Mix.Sprite

  @impl Mix.Task
  def run(argv) do
    {opts, _args} = Sprite.parse_args(argv)
    sprite = Sprite.existing_sprite!(opts)

    # The app first, so nothing is left holding database connections.
    Sprite.stop_service!(sprite, Sprite.phoenix_service())
    Sprite.stop_service!(sprite, Sprite.postgres_service())
  end
end
