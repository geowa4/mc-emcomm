defmodule Mix.Tasks.Sprite.Connect do
  @shortdoc "Opens an interactive session in the app's Sprite"

  @moduledoc """
  Opens a terminal session in the sprite created by `mix sprite.up`, starting
  in the repository directory, through the local `sprite` CLI (which must be
  installed and logged in).

      mix sprite.connect [--name NAME] [-- COMMAND [ARGS...]]

  Without a command it starts a login shell; with one it runs that command
  instead, for example `mix sprite.connect -- claude`. Detach with Ctrl-\\ to
  leave the session running: `sprite sessions` lists sessions and
  `sprite attach` reconnects to one.

  When the session ends, the task offers to take a checkpoint of the sprite
  (`--no-checkpoint` skips the question).

      mix sprite.connect [--name NAME] [--no-checkpoint] [-- COMMAND [ARGS...]]
  """
  use Mix.Task

  alias Mix.Sprite

  @switches [checkpoint: :boolean]
  @default_command ~w(bash -l)
  @default_comment "mix sprite.connect"

  @impl Mix.Task
  def run(argv) do
    {opts, args} = Sprite.parse_args(argv, @switches)
    sprite = Sprite.existing_sprite!(opts)
    dir = Path.join(Sprite.home(), Sprite.repo_name(Sprite.origin_url!()))
    command = if args == [], do: @default_command, else: args

    status =
      Sprite.sprite_cli!(["exec", "-s", sprite.name, "--tty", "--dir", dir, "--" | command])

    if Keyword.get(opts, :checkpoint, true), do: offer_checkpoint(sprite)
    if status != 0, do: exit({:shutdown, status})
  end

  defp offer_checkpoint(sprite) do
    if Mix.shell().yes?("Create a checkpoint of sprite #{sprite.name}?") do
      Sprite.create_checkpoint!(sprite, comment())
    end
  end

  defp comment do
    case Mix.shell().prompt("Comment [#{@default_comment}]:") do
      :eof -> @default_comment
      input -> if String.trim(input) == "", do: @default_comment, else: String.trim(input)
    end
  end
end
