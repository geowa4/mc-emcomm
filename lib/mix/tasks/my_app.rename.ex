defmodule Mix.Tasks.MyApp.Rename do
  @shortdoc "Renames the starter template to your app's names (run once)"

  @moduledoc """
  Renames the `my_app` / `my-app` / `MyApp` / `MyAppWeb` placeholders to your
  project's names, in file contents and paths, then deletes itself and its test.

      mix my_app.rename --otp <snake_case_otp_app> --module <PascalCaseModule>
  """
  use Mix.Task

  @switches [otp: :string, module: :string]
  @skip_dirs ~w(_build deps .git priv/static assets/node_modules node_modules)
  @self "lib/mix/tasks/my_app.rename.ex"
  @self_test "test/mix/tasks/my_app.rename_test.exs"

  @impl Mix.Task
  def run(argv) do
    {opts, _, _} = OptionParser.parse(argv, switches: @switches)

    otp = opts[:otp] || Mix.raise("--otp <snake_case_otp_app> is required")
    module = opts[:module] || Mix.raise("--module <PascalCaseModule> is required")

    validate_snake_case!(otp)
    validate_pascal_case!(module)

    # Substitution order matters: the most specific token first, so that
    # MyAppWeb is not partially rewritten by the MyApp rule. The kebab-case form
    # is used where underscores are not allowed (Fly app names and hostnames).
    subs = [
      {"MyAppWeb", module <> "Web"},
      {"MyApp", module},
      {"my_app", otp},
      {"my-app", String.replace(otp, "_", "-")}
    ]

    files = collect_files(".")

    # 1. Rewrite file contents.
    Enum.each(files, fn path -> rewrite_contents(path, subs) end)

    # 2. Rename paths, longest path first so parent renames do not invalidate
    #    child paths still queued.
    files
    |> Enum.filter(&String.contains?(&1, "my_app"))
    |> Enum.sort_by(&String.length/1, :desc)
    |> Enum.each(fn path -> rename_path(path, otp) end)

    # 3. Remove directories emptied by the renames.
    remove_empty_dirs(".")

    # 4. Delete this task (and its test) so it cannot run twice.
    File.rm(@self)
    File.rm(@self_test)

    # 5. Longer names can push lines past the formatter's limit.
    if File.exists?(".formatter.exs"), do: Mix.Task.rerun("format")

    Mix.shell().info("""

    Renamed to #{module} (#{otp}). Next steps:

        mix setup
        mix usage_rules.sync   # restores the managed section in AGENTS.md
        mix precommit
        mix phx.server
    """)
  end

  defp validate_snake_case!(s) do
    unless Regex.match?(~r/^[a-z][a-z0-9_]*$/, s) do
      Mix.raise("--otp must be snake_case, got: #{inspect(s)}")
    end
  end

  defp validate_pascal_case!(s) do
    unless Regex.match?(~r/^[A-Z][A-Za-z0-9]*$/, s) do
      Mix.raise("--module must be PascalCase, got: #{inspect(s)}")
    end
  end

  defp collect_files(root) do
    root
    |> Path.join("**/*")
    |> Path.wildcard(match_dot: true)
    |> Enum.map(&Path.relative_to(&1, root))
    |> Enum.reject(fn path ->
      File.dir?(path) or skipped?(path) or path in [@self, @self_test]
    end)
  end

  # Skips paths whose leading segments match a skip dir (so `.git/` is skipped
  # but `.github/` and `.gitignore` are not).
  defp skipped?(path) do
    Enum.any?(@skip_dirs, fn dir -> path == dir or String.starts_with?(path, dir <> "/") end)
  end

  defp rewrite_contents(path, subs) do
    case File.read(path) do
      {:ok, contents} ->
        new =
          Enum.reduce(subs, contents, fn {from, to}, acc ->
            String.replace(acc, from, to)
          end)

        if new != contents, do: File.write!(path, new)

      {:error, _} ->
        :ok
    end
  end

  defp rename_path(path, otp) do
    new_path = String.replace(path, "my_app", otp)

    if new_path != path do
      File.mkdir_p!(Path.dirname(new_path))
      File.rename!(path, new_path)
    end
  end

  # Deepest first, so a parent is only checked after its emptied children are gone.
  defp remove_empty_dirs(root) do
    root
    |> Path.join("**/*")
    |> Path.wildcard(match_dot: true)
    |> Enum.map(&Path.relative_to(&1, root))
    |> Enum.filter(fn path ->
      String.contains?(path, "my_app") and File.dir?(path) and not skipped?(path)
    end)
    |> Enum.sort_by(&String.length/1, :desc)
    |> Enum.each(fn dir -> if File.ls!(dir) == [], do: File.rmdir!(dir) end)
  end
end
