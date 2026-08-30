defmodule Mix.Tasks.Sprite.Down do
  @shortdoc "Destroys the app's Sprite and removes its deploy key"

  @moduledoc """
  Destroys the sprite created by `mix sprite.up`, including all of its
  checkpoints, and removes the deploy key it registered on the GitHub
  repository. Asks for confirmation first unless `--yes` is given.

      mix sprite.down [--name NAME] [--yes]

  To keep the sprite but stop its services, use `mix sprite.stop` instead.
  """
  use Mix.Task

  alias Mix.Sprite

  @switches [yes: :boolean]

  @impl Mix.Task
  def run(argv) do
    {opts, _args} = Sprite.parse_args(argv, @switches)
    sprite = Sprite.existing_sprite!(opts)

    if Keyword.get(opts, :yes, false) or confirmed?(sprite) do
      destroy(sprite)
      remove_deploy_key(sprite)
    else
      Mix.shell().info("Aborted; sprite #{sprite.name} was left alone")
    end
  end

  defp confirmed?(sprite) do
    Mix.shell().yes?(
      "Destroy sprite #{sprite.name} and all of its checkpoints?",
      default: :no
    )
  end

  defp destroy(sprite) do
    Sprite.step("Destroying sprite #{sprite.name}")

    case Sprites.destroy(sprite) do
      :ok -> Sprite.info("Destroyed")
      {:error, reason} -> Mix.raise("Could not destroy sprite #{sprite.name}: #{inspect(reason)}")
    end
  end

  # Best effort: the sprite is already gone, so a missing `gh` or a non-GitHub
  # remote only gets reported.
  defp remove_deploy_key(sprite) do
    title = Sprite.deploy_key_title(sprite.name)

    with repo when is_binary(repo) <- Sprite.github_repo(Sprite.origin_url!()),
         {:ok, keys} <- Sprite.deploy_keys(repo),
         {id, ^title} <- Enum.find(keys, &match?({_id, ^title}, &1)) do
      Sprite.step("Removing deploy key #{inspect(title)} from #{repo}")

      case Sprite.gh(["api", "-X", "DELETE", "repos/#{repo}/keys/#{id}"]) do
        {:ok, _out} -> Sprite.info("Removed")
        {:error, out} -> Sprite.info("Could not remove the deploy key: #{out}")
      end
    else
      nil ->
        Sprite.info("No deploy key #{inspect(title)} to remove")

      {:error, out} ->
        Sprite.info("Could not list deploy keys (remove #{inspect(title)} by hand): #{out}")
    end
  end
end
