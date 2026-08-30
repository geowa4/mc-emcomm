defmodule Mix.Tasks.Sync do
  @shortdoc "Rebases the current branch onto the latest commit of origin's default branch"

  @moduledoc """
  Fetches `origin` and rebases the checked-out branch onto origin's default
  branch (`origin/HEAD`, re-read from the remote each time).

      mix sync

  A rebase that stops on conflicts is left in progress for you to resolve
  (`git status` shows the conflicted files; finish with `git rebase --continue`
  or give up with `git rebase --abort`) and the task fails. Uncommitted changes
  make git refuse to start the rebase, which fails the task as well.

  The same for the app's Sprite is `mix sprite.sync`.
  """
  use Mix.Task

  @impl Mix.Task
  def run(_argv) do
    branch =
      git!(["symbolic-ref", "-q", "--short", "HEAD"], "HEAD is detached; check out a branch")

    before = git!(["rev-parse", "HEAD"])

    info(git!(["fetch", "--prune", "origin"]))
    git!(["remote", "set-head", "origin", "--auto"])
    default = git!(["symbolic-ref", "-q", "--short", "refs/remotes/origin/HEAD"])

    Mix.shell().info([:cyan, "==> ", :reset, "Rebasing #{branch} onto #{default}"])

    case git(["rebase", "--no-autostash", default]) do
      {out, 0} ->
        info(out)
        report(branch, default, before, git!(["rev-parse", "HEAD"]))

      {out, code} ->
        info(out)

        Mix.raise("""
        Rebasing #{branch} onto #{default} failed (git exited with status #{code}).
        Resolve the conflicts and run `git rebase --continue`, or run `git rebase --abort`.
        """)
    end
  end

  defp report(branch, default, sha, sha) do
    Mix.shell().info("#{branch} is already up to date with #{default} at #{short(sha)}")
  end

  defp report(branch, default, before, after_) do
    Mix.shell().info("#{branch} is now on #{default} (#{short(before)} -> #{short(after_)})")
  end

  defp short(sha), do: String.slice(sha, 0, 7)

  defp git(args), do: System.cmd("git", args, stderr_to_stdout: true)

  defp git!(args, message \\ nil) do
    case git(args) do
      {out, 0} ->
        String.trim(out)

      {out, _code} ->
        Mix.raise(message || "git #{Enum.join(args, " ")} failed: #{String.trim(out)}")
    end
  end

  defp info(""), do: :ok

  defp info(out) do
    out |> String.trim() |> String.split("\n") |> Enum.each(&Mix.shell().info("    " <> &1))
  end
end
