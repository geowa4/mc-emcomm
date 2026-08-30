defmodule Mix.Tasks.SyncTest do
  # Changes the working directory and the Mix shell, so it cannot run concurrently.
  use ExUnit.Case, async: false

  @moduletag :tmp_dir

  setup %{tmp_dir: tmp_dir} do
    shell = Mix.shell()
    Mix.shell(Mix.Shell.Process)
    on_exit(fn -> Mix.shell(shell) end)

    # Keep the developer's own git config (commit signing, hooks, aliases) out
    # of the fixture repositories and the task under test.
    config = Path.join(tmp_dir, "gitconfig")

    File.write!(
      config,
      "[user]\n\tname = Test\n\temail = test@example.com\n[commit]\n\tgpgsign = false\n"
    )

    previous = Enum.map(~w(GIT_CONFIG_GLOBAL GIT_CONFIG_NOSYSTEM), &{&1, System.get_env(&1)})
    System.put_env("GIT_CONFIG_GLOBAL", config)
    System.put_env("GIT_CONFIG_NOSYSTEM", "1")
    on_exit(fn -> Enum.each(previous, fn {key, value} -> restore_env(key, value) end) end)

    origin = Path.join(tmp_dir, "origin.git")
    upstream = Path.join(tmp_dir, "upstream")
    local = Path.join(tmp_dir, "local")

    git!(tmp_dir, ["init", "-q", "--bare", "--initial-branch=main", origin])
    git!(tmp_dir, ["clone", "-q", origin, upstream])
    commit!(upstream, "README.md", "one\n", "one")
    git!(upstream, ["push", "-q", "-u", "origin", "main"])
    git!(tmp_dir, ["clone", "-q", origin, local])

    %{upstream: upstream, local: local}
  end

  test "rebases the current branch onto origin's default branch", %{
    upstream: upstream,
    local: local
  } do
    git!(local, ["checkout", "-q", "-b", "feature"])
    commit!(local, "feature.txt", "feature\n", "feature")
    commit!(upstream, "README.md", "two\n", "two")
    git!(upstream, ["push", "-q"])

    File.cd!(local, fn -> Mix.Tasks.Sync.run([]) end)

    assert File.read!(Path.join(local, "README.md")) == "two\n"
    assert git!(local, ["log", "--format=%s", "origin/main..feature"]) == "feature"
    assert git!(local, ["merge-base", "--is-ancestor", "origin/main", "feature"]) == ""
    assert_received {:mix_shell, :info, ["feature is now on origin/main" <> _]}
  end

  test "reports when already up to date", %{local: local} do
    File.cd!(local, fn -> Mix.Tasks.Sync.run([]) end)

    assert_received {:mix_shell, :info, ["main is already up to date with origin/main" <> _]}
  end

  test "fails and leaves a conflicting rebase in progress", %{upstream: upstream, local: local} do
    commit!(local, "README.md", "mine\n", "mine")
    commit!(upstream, "README.md", "theirs\n", "theirs")
    git!(upstream, ["push", "-q"])

    assert_raise Mix.Error, ~r/Rebasing main onto origin\/main failed/, fn ->
      File.cd!(local, fn -> Mix.Tasks.Sync.run([]) end)
    end

    assert File.dir?(Path.join(local, ".git/rebase-merge"))
    assert git!(local, ["diff", "--name-only", "--diff-filter=U"]) == "README.md"
  end

  test "fails on a detached HEAD", %{local: local} do
    git!(local, ["checkout", "-q", "--detach"])

    assert_raise Mix.Error, ~r/HEAD is detached/, fn ->
      File.cd!(local, fn -> Mix.Tasks.Sync.run([]) end)
    end
  end

  defp commit!(repo, file, contents, message) do
    File.write!(Path.join(repo, file), contents)
    git!(repo, ["add", file])

    git!(repo, ["commit", "-q", "-m", message])
  end

  defp restore_env(key, nil), do: System.delete_env(key)
  defp restore_env(key, value), do: System.put_env(key, value)

  defp git!(dir, args) do
    {out, 0} = System.cmd("git", args, cd: dir, stderr_to_stdout: true)
    String.trim(out)
  end
end
