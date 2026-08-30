defmodule Mix.Tasks.Sprite.Checkpoint do
  @shortdoc "Creates, lists, or restores checkpoints of the app's Sprite"

  @moduledoc """
  Manages checkpoints of the sprite created by `mix sprite.up`.

      mix sprite.checkpoint create [--comment TEXT] [--name NAME]
      mix sprite.checkpoint list [--name NAME]
      mix sprite.checkpoint restore ID [--name NAME]

  A checkpoint snapshots the sprite's filesystem, not its running processes.
  Restoring one restarts the environment: the `postgres` and `phoenix` services
  come back from their on-disk definitions, anything else that was running is
  gone, and open `sprite console` sessions end.
  """
  use Mix.Task

  alias Mix.Sprite

  @switches [comment: :string]

  @impl Mix.Task
  def run(argv) do
    {opts, args} = Sprite.parse_args(argv, @switches)

    case args do
      ["create"] ->
        comment = Keyword.get(opts, :comment, "mix sprite.checkpoint")
        Sprite.create_checkpoint!(Sprite.existing_sprite!(opts), comment)

      ["list"] ->
        list(Sprite.existing_sprite!(opts))

      ["restore", id] ->
        Sprite.restore_checkpoint!(Sprite.existing_sprite!(opts), id)

      _other ->
        Mix.raise("""
        Usage:
            mix sprite.checkpoint create [--comment TEXT]
            mix sprite.checkpoint list
            mix sprite.checkpoint restore ID
        """)
    end
  end

  defp list(sprite) do
    case Sprite.checkpoints!(sprite) do
      [] -> Mix.shell().info("No checkpoints yet")
      checkpoints -> Enum.each(checkpoints, &Mix.shell().info(format(&1)))
    end
  end

  defp format(checkpoint) do
    created =
      case checkpoint.create_time do
        %DateTime{} = time -> DateTime.to_iso8601(time)
        _ -> ""
      end

    String.pad_trailing(checkpoint.id, 12) <>
      String.pad_trailing(created, 22) <> (checkpoint.comment || "")
  end
end
