defmodule Mix.Sprite do
  @moduledoc """
  Shared plumbing for the `mix sprite.*` tasks, which manage a Fly.io Sprite
  (https://sprites.dev) holding a complete development copy of this
  application: PostgreSQL and `mix phx.server` as Sprite services and the
  repository cloned over SSH.

  The SDK authenticates with `SPRITES_TOKEN`, an API token from
  https://sprites.dev/account. The `sprite` CLI stores its own token encrypted,
  so the tasks cannot borrow it. See CONTRIBUTING.md § Sprites.
  """

  alias Sprites.Sprite

  @home "/home/sprite"
  @postgres_service "postgres"
  @phoenix_service "phoenix"
  @http_port 4000
  @quick_timeout :timer.minutes(2)
  @idle_timeout :timer.minutes(15)
  @switches [name: :string]

  def home, do: @home
  def postgres_service, do: @postgres_service
  def phoenix_service, do: @phoenix_service
  def http_port, do: @http_port

  ## Task plumbing

  @doc """
  Parses `argv`, accepting `--name` plus any task-specific `switches`.
  """
  @spec parse_args([String.t()], keyword()) :: {keyword(), [String.t()]}
  def parse_args(argv, switches \\ []) do
    case OptionParser.parse(argv, strict: @switches ++ switches) do
      {opts, args, []} ->
        {opts, args}

      {_opts, _args, invalid} ->
        Mix.raise("Unknown or invalid options: #{Enum.map_join(invalid, ", ", &elem(&1, 0))}")
    end
  end

  @doc "Builds an SDK client from `SPRITES_TOKEN`."
  @spec client!() :: Sprites.Client.t()
  def client! do
    case System.get_env("SPRITES_TOKEN") do
      token when is_binary(token) and token != "" ->
        {:ok, _apps} = Application.ensure_all_started(:sprites)
        Sprites.new(token)

      _ ->
        Mix.raise("""
        SPRITES_TOKEN is not set.

        Create an API token at https://sprites.dev/account and export it before
        running the sprite tasks:

            export SPRITES_TOKEN=...
        """)
    end
  end

  @doc "The sprite name: `--name`, else the repository name from the git remote."
  @spec sprite_name(keyword()) :: String.t()
  def sprite_name(opts), do: Keyword.get(opts, :name) || repo_name(origin_url!())

  @doc "Returns a handle to an existing sprite, raising if it does not exist."
  @spec existing_sprite!(keyword()) :: Sprite.t()
  def existing_sprite!(opts) do
    client = client!()
    name = sprite_name(opts)

    case Sprites.get_sprite(client, name) do
      {:ok, attrs} ->
        Sprite.new(client, name, attrs)

      {:error, {:not_found, _body}} ->
        Mix.raise("Sprite #{inspect(name)} does not exist. Run `mix sprite.up` to create it.")

      {:error, reason} ->
        raise_lookup_error(name, reason)
    end
  end

  @doc "Returns a handle to the sprite, creating it when it does not exist yet."
  @spec ensure_sprite!(keyword()) :: {Sprite.t(), :created | :existing}
  def ensure_sprite!(opts) do
    client = client!()
    name = sprite_name(opts)

    case Sprites.get_sprite(client, name) do
      {:ok, attrs} ->
        {Sprite.new(client, name, attrs), :existing}

      {:error, {:not_found, _body}} ->
        create_sprite!(client, name)

      {:error, reason} ->
        raise_lookup_error(name, reason)
    end
  end

  @spec raise_lookup_error(String.t(), term()) :: no_return()
  defp raise_lookup_error(_name, {:api_error, 401, _body}) do
    Mix.raise("""
    api.sprites.dev rejected SPRITES_TOKEN (401).

    It must be a Sprites API token (the `org/org-id/token-id/token-value` form
    issued at https://sprites.dev/account), not a Fly.io `FlyV1 ...` token.
    """)
  end

  defp raise_lookup_error(name, reason) do
    Mix.raise("Could not look up sprite #{inspect(name)}: #{inspect(reason)}")
  end

  defp create_sprite!(client, name) do
    case Sprites.create(client, name) do
      {:ok, sprite} ->
        {sprite, :created}

      {:error, reason} ->
        Mix.raise("Could not create sprite #{inspect(name)}: #{inspect(reason)}")
    end
  end

  @doc "The sprite's URL as reported by the API."
  @spec url(Sprite.t()) :: String.t()
  def url(%Sprite{client: client, name: name}) do
    case Sprites.get_sprite(client, name) do
      {:ok, %{"url" => url}} when is_binary(url) -> url
      _ -> "(unknown; run `sprite url -s #{name}`)"
    end
  end

  ## Local git

  @doc "The `origin` remote URL of the current repository."
  @spec origin_url!() :: String.t()
  def origin_url!, do: git!(["remote", "get-url", "origin"])

  @doc "The checked-out branch of the current repository."
  @spec current_branch!() :: String.t()
  def current_branch!, do: git!(["rev-parse", "--abbrev-ref", "HEAD"])

  @doc "A git config value, or nil when unset."
  @spec git_config(String.t()) :: String.t() | nil
  def git_config(key) do
    case System.cmd("git", ["config", "--get", key], stderr_to_stdout: true) do
      {out, 0} -> String.trim(out)
      _ -> nil
    end
  end

  defp git!(args) do
    case System.cmd("git", args, stderr_to_stdout: true) do
      {out, 0} -> String.trim(out)
      {out, _code} -> Mix.raise("git #{Enum.join(args, " ")} failed: #{String.trim(out)}")
    end
  end

  @doc """
  The repository name of a git URL.

      iex> Mix.Sprite.repo_name("git@github.com:acme/app.git")
      "app"
  """
  @spec repo_name(String.t()) :: String.t()
  def repo_name(url) do
    url
    |> String.trim()
    |> String.trim_trailing("/")
    |> Path.basename()
    |> String.replace_suffix(".git", "")
  end

  @doc """
  The host of an SSH git URL (`git@host:path` or `ssh://git@host/path`), or
  nil for any other transport.
  """
  @spec ssh_host(String.t()) :: String.t() | nil
  def ssh_host(url) do
    cond do
      String.starts_with?(url, "ssh://") -> capture(~r{^ssh://(?:[^@/]+@)?([^:/]+)}, url)
      String.contains?(url, "://") -> nil
      true -> capture(~r{^(?:[^@/]+@)?([^:/]+):}, url)
    end
  end

  @doc """
  The `owner/repo` of a GitHub remote (SSH or HTTPS), or nil for other hosts.
  """
  @spec github_repo(String.t()) :: String.t() | nil
  def github_repo(url) do
    capture(
      ~r{^(?:git@github\.com:|ssh://git@github\.com/|https://github\.com/)([^/]+/[^/]+?)(?:\.git)?/?$},
      String.trim(url)
    )
  end

  @doc "The Elixir version pinned in a `mise.toml` file's contents, or nil."
  @spec elixir_version(String.t()) :: String.t() | nil
  def elixir_version(mise_toml) do
    capture(~r/^elixir\s*=\s*"(\d+\.\d+\.\d+)/m, mise_toml)
  end

  ## Remote execution
  #
  # Scripts run under a non-login `bash -c`: the exec environment already has
  # the sprite's full PATH, and a login shell would run ~/.bash_logout on exit,
  # where `clear_console` fails without a tty and, under `set -e`, turns an
  # explicit `exit 0` into exit status 1.

  @doc """
  Runs a bash script on the sprite and returns `{output, exit_code}` with
  stderr merged into the output.
  """
  @spec sh(Sprite.t(), String.t(), keyword()) :: {binary(), non_neg_integer()}
  def sh(sprite, script, opts \\ []) do
    opts = Keyword.merge([stderr_to_stdout: true, timeout: @quick_timeout], opts)
    Sprites.cmd(sprite, "bash", ["-c", script], opts)
  end

  @doc "Like `sh/3`, but raises unless the script exits 0. Returns trimmed output."
  @spec sh!(Sprite.t(), String.t(), keyword()) :: String.t()
  def sh!(sprite, script, opts \\ []) do
    case sh(sprite, script, opts) do
      {out, 0} -> String.trim(out)
      {out, code} -> Mix.raise("Remote command exited with status #{code}:\n#{String.trim(out)}")
    end
  end

  @doc """
  Runs a bash script on the sprite, streaming its output to the terminal.
  Raises unless the script exits 0. Use it for long-running steps.
  """
  @spec stream!(Sprite.t(), String.t(), keyword()) :: :ok
  def stream!(sprite, script, opts \\ []) do
    case Sprites.spawn(sprite, "bash", ["-c", script], Keyword.take(opts, [:env, :dir])) do
      {:ok, cmd} -> relay(cmd)
      {:error, reason} -> Mix.raise("Could not start remote command: #{inspect(reason)}")
    end
  end

  defp relay(%{ref: ref} = cmd) do
    receive do
      {kind, %{ref: ^ref}, data} when kind in [:stdout, :stderr] ->
        IO.write(data)
        relay(cmd)

      {:exit, %{ref: ^ref}, 0} ->
        :ok

      {:exit, %{ref: ^ref}, code} ->
        Mix.raise("Remote command exited with status #{code}")

      {:error, %{ref: ^ref}, reason} ->
        Mix.raise("Remote command failed: #{inspect(reason)}")
    after
      @idle_timeout ->
        Mix.raise(
          "Remote command produced no output for #{div(@idle_timeout, 60_000)} minutes; giving up"
        )
    end
  end

  ## Local `sprite` and `gh` CLIs

  @doc """
  Hands the terminal over to the local `sprite` CLI with `args` and returns
  its exit status. Interactive sessions need the real terminal (raw mode,
  resizes, signals), which the SDK's stdin relay cannot provide.
  """
  @spec sprite_cli!([String.t()]) :: non_neg_integer()
  def sprite_cli!(args) do
    exe =
      System.find_executable("sprite") ||
        Mix.raise("The `sprite` CLI is not installed; see https://sprites.dev")

    # :nouse_stdio leaves the VM's own stdin/stdout/stderr to the child, so it
    # inherits the terminal instead of talking to the VM through pipes.
    port = Port.open({:spawn_executable, exe}, [:nouse_stdio, :exit_status, args: args])

    receive do
      {^port, {:exit_status, code}} -> code
    end
  end

  @doc "The title of the deploy key `mix sprite.up` registers for a sprite."
  @spec deploy_key_title(String.t()) :: String.t()
  def deploy_key_title(sprite_name), do: "sprite #{sprite_name}"

  @doc "The deploy keys of a GitHub `owner/repo` as `{id, title}` pairs."
  @spec deploy_keys(String.t()) :: {:ok, [{integer(), String.t()}]} | {:error, String.t()}
  def deploy_keys(repo) do
    with {:ok, json} <- gh(["api", "repos/#{repo}/keys"]) do
      {:ok, json |> Jason.decode!() |> Enum.map(&{&1["id"], &1["title"]})}
    end
  end

  @doc "Runs the GitHub CLI, returning its trimmed output or the error output."
  @spec gh([String.t()]) :: {:ok, String.t()} | {:error, String.t()}
  def gh(args) do
    case System.cmd("gh", args, stderr_to_stdout: true) do
      {out, 0} -> {:ok, String.trim(out)}
      {out, _code} -> {:error, String.trim(out)}
    end
  rescue
    ErlangError -> {:error, "`gh` (GitHub CLI) is not installed"}
  end

  @doc "Like `gh/1`, but raises on failure."
  @spec gh!([String.t()]) :: String.t()
  def gh!(args) do
    case gh(args) do
      {:ok, out} -> out
      {:error, out} -> Mix.raise("gh #{Enum.join(args, " ")} failed:\n#{out}")
    end
  end

  ## Services (`sprite-env services`, the in-VM service manager)

  @doc "The sprite's services as decoded JSON maps."
  @spec services(Sprite.t()) :: [map()]
  def services(sprite) do
    sprite |> sh!("sprite-env services list") |> Jason.decode!()
  end

  @doc "The status of a service (running, stopped, failed, ...) or nil when undefined."
  @spec service_status(Sprite.t(), String.t()) :: String.t() | nil
  def service_status(sprite, name) do
    case Enum.find(services(sprite), &(&1["name"] == name)) do
      %{"state" => %{"status" => status}} -> status
      _ -> nil
    end
  end

  @doc "Creates the service with `create_flags` when missing; starts it when not running."
  @spec ensure_service!(Sprite.t(), String.t(), String.t()) :: :ok
  def ensure_service!(sprite, name, create_flags) do
    case service_status(sprite, name) do
      nil ->
        step("Creating service #{name}")
        sh!(sprite, "sprite-env services create #{name} #{create_flags} --no-stream")

      "running" ->
        info("Service #{name} is running")

      _status ->
        start_service!(sprite, name)
    end

    :ok
  end

  @doc "Starts a defined service, printing progress."
  @spec start_service!(Sprite.t(), String.t()) :: :ok
  def start_service!(sprite, name) do
    step("Starting service #{name}")
    sh!(sprite, "sprite-env services start #{name} --no-stream")
    :ok
  end

  @doc "Stops the service when it is defined and not already stopped."
  @spec stop_service!(Sprite.t(), String.t()) :: :ok
  def stop_service!(sprite, name) do
    case service_status(sprite, name) do
      nil ->
        info("Service #{name} is not defined")

      "stopped" ->
        info("Service #{name} is already stopped")

      _status ->
        step("Stopping service #{name}")

        # A service in a failed state can reject the stop request (409); report
        # it rather than abort, so the remaining services still get stopped.
        case sh(sprite, "sprite-env services stop #{name} --no-stream") do
          {_out, 0} -> :ok
          {out, code} -> info("Stop of #{name} exited with status #{code}: #{String.trim(out)}")
        end
    end

    :ok
  end

  ## Checkpoints

  @doc "Creates a checkpoint, printing progress. Returns the new checkpoint id when reported."
  @spec create_checkpoint!(Sprite.t(), String.t()) :: String.t() | nil
  def create_checkpoint!(sprite, comment) do
    step("Creating checkpoint")

    case Sprites.create_checkpoint(sprite, comment: comment) do
      {:ok, messages} ->
        Enum.each(messages, &print_message/1)
        Enum.find_value(messages, &checkpoint_id/1)

      {:error, reason} ->
        Mix.raise("Could not create checkpoint: #{inspect(reason)}")
    end
  end

  @doc """
  Creates a checkpoint with `comment` unless one with that comment already
  exists. Returns the checkpoint id when known.
  """
  @spec ensure_checkpoint!(Sprite.t(), String.t()) :: String.t() | nil
  def ensure_checkpoint!(sprite, comment) do
    case Enum.find(checkpoints!(sprite), &(&1.comment == comment)) do
      nil ->
        create_checkpoint!(sprite, comment)

      checkpoint ->
        info("Checkpoint #{checkpoint.id} (#{comment}) already exists")
        checkpoint.id
    end
  end

  @doc "The sprite's checkpoints."
  @spec checkpoints!(Sprite.t()) :: [Sprites.Checkpoint.t()]
  def checkpoints!(sprite) do
    case Sprites.list_checkpoints(sprite) do
      {:ok, checkpoints} -> checkpoints
      {:error, reason} -> Mix.raise("Could not list checkpoints: #{inspect(reason)}")
    end
  end

  @doc "Restores a checkpoint, printing progress."
  @spec restore_checkpoint!(Sprite.t(), String.t()) :: :ok
  def restore_checkpoint!(sprite, id) do
    step("Restoring checkpoint #{id}")

    case Sprites.restore_checkpoint(sprite, id) do
      {:ok, messages} -> Enum.each(messages, &print_message/1)
      {:error, reason} -> Mix.raise("Could not restore checkpoint #{id}: #{inspect(reason)}")
    end
  end

  defp print_message(%{type: "error"} = message) do
    Mix.raise("Sprite reported an error: #{message.error || message.data}")
  end

  defp print_message(%{data: data}) when is_binary(data), do: info(String.trim_trailing(data))
  defp print_message(_message), do: :ok

  defp checkpoint_id(%{data: data}) when is_binary(data),
    do: capture(~r/Checkpoint (\S+) created/, data)

  defp checkpoint_id(_message), do: nil

  ## Terminal output

  @doc "Prints a step heading."
  @spec step(String.t()) :: :ok
  def step(message), do: Mix.shell().info([:cyan, "==> ", :reset, message])

  @doc "Prints an indented detail line."
  @spec info(String.t()) :: :ok
  def info(message), do: Mix.shell().info("    " <> message)

  defp capture(regex, string) do
    case Regex.run(regex, string, capture: :all_but_first) do
      [value] -> value
      _ -> nil
    end
  end
end
