defmodule Mix.Tasks.Sprite.Up do
  @shortdoc "Creates and provisions a Sprite dev VM running this app"

  @moduledoc """
  Creates a Fly.io Sprite (https://sprites.dev) and provisions it as a
  complete development environment for this application:

    1. creates the sprite (`--name`, default: the repository name)
    2. installs PostgreSQL and runs it as the `postgres` Sprite service
       (`postgres`/`postgres` on `localhost:5432`, matching `config/dev.exs`)
    3. installs the Elixir version pinned in `mise.toml`
    4. gives the sprite GitHub access and clones this repository's current
       branch into `/home/sprite/<repo>`: by default a key pair generated
       inside the sprite is registered as a write-enabled deploy key on the
       repository with `gh`; `--ssh-key PATH` copies an existing private key
       instead (required for non-GitHub remotes). Your git identity is copied
       either way
    5. runs `mix setup`
    6. runs `mix phx.server` as the `phoenix` Sprite service and routes the
       sprite's URL to it
    7. takes a checkpoint of the running app

  Claude Code is preinstalled in the sprite but not signed in; run
  `mix sprite.connect -- claude` and use `/login`.

  Every step is idempotent, so re-running the task after a failure (or after
  `mix sprite.stop`) resumes where it left off. Requires `SPRITES_TOKEN`; see
  CONTRIBUTING.md § Sprites.

      mix sprite.up [--name NAME] [--ssh-key PATH] [--no-checkpoint]

  ## Options

    * `--name` - sprite name (default: repository name)
    * `--ssh-key` - private key file to copy into the sprite instead of
      registering a per-sprite deploy key
    * `--no-checkpoint` - skip the checkpoint
  """
  use Mix.Task

  alias Mix.Sprite
  alias Sprites.Filesystem

  @switches [ssh_key: :string, checkpoint: :boolean]
  @sprite_key ".ssh/id_ed25519"
  @apt_packages ~w(postgresql build-essential inotify-tools)

  @impl Mix.Task
  def run(argv) do
    {opts, _args} = Sprite.parse_args(argv, @switches)

    # Validate local inputs before touching the API.
    origin = Sprite.origin_url!()
    ssh_key = ssh_key_source!(opts, origin)
    elixir = elixir_version!()
    branch = Sprite.current_branch!()
    dest = Path.join(Sprite.home(), Sprite.repo_name(origin))

    {sprite, status} = Sprite.ensure_sprite!(opts)
    Sprite.step("Sprite #{sprite.name} #{status}")

    install_packages(sprite)
    ensure_postgres(sprite)
    install_elixir(sprite, elixir)
    install_ssh_key(sprite, ssh_key, origin)
    configure_git(sprite)
    clone_repo(sprite, origin, branch, dest)
    setup_app(sprite, dest)
    ensure_phoenix(sprite, dest)
    checkpoint(sprite, opts, "mix sprite.up: app running")
    summary(sprite)
  end

  # Re-running the task must not pile up checkpoints: one per comment.
  defp checkpoint(sprite, opts, comment) do
    if Keyword.get(opts, :checkpoint, true), do: Sprite.ensure_checkpoint!(sprite, comment)
  end

  ## Local inputs

  # Either `{:file, path}` (copy an existing key) or `{:deploy_key, "owner/repo"}`
  # (generate one in the sprite and register it on GitHub).
  defp ssh_key_source!(opts, origin) do
    case {Keyword.get(opts, :ssh_key), Sprite.github_repo(origin)} do
      {nil, nil} ->
        Mix.raise("#{origin} is not a GitHub remote, so pass --ssh-key PATH")

      {nil, repo} ->
        gh_authenticated!()
        {:deploy_key, repo}

      {path, _repo} ->
        expanded = Path.expand(path)
        File.regular?(expanded) || Mix.raise("SSH key #{path} does not exist")
        {:file, expanded}
    end
  end

  defp gh_authenticated! do
    case Sprite.gh(["auth", "status"]) do
      {:ok, _out} ->
        :ok

      {:error, out} ->
        Mix.raise("""
        `gh` must be installed and logged in to add a deploy key (or pass --ssh-key):
        #{out}
        """)
    end
  end

  defp elixir_version! do
    with {:ok, contents} <- File.read("mise.toml"),
         version when is_binary(version) <- Sprite.elixir_version(contents) do
      version
    else
      _ -> Mix.raise("Could not read the elixir version from mise.toml")
    end
  end

  ## Provisioning steps (each one is safe to repeat)

  defp install_packages(sprite) do
    Sprite.step("Installing #{Enum.join(@apt_packages, ", ")}")

    Sprite.stream!(sprite, """
    set -euo pipefail
    if dpkg -s #{Enum.join(@apt_packages, " ")} >/dev/null 2>&1; then
      echo "already installed"
      exit 0
    fi
    sudo apt-get update -qq
    sudo apt-get install -y -qq #{Enum.join(@apt_packages, " ")}
    """)
  end

  defp ensure_postgres(sprite) do
    Sprite.step("Configuring PostgreSQL")

    version =
      Sprite.sh!(sprite, """
      set -euo pipefail
      version=$(pg_lsclusters -h | awk 'NR == 1 { print $1 }')
      hba="/etc/postgresql/$version/main/pg_hba.conf"
      # Inside a sprite `localhost` also resolves to an IPv6 address that the
      # packaged pg_hba.conf does not cover.
      grep -q '^host all all all scram-sha-256' "$hba" ||
        echo 'host all all all scram-sha-256' | sudo tee -a "$hba" >/dev/null
      echo "$version"
      """)

    # The packaged cluster must only ever run under the Sprite service manager;
    # make sure the package's own init did not leave it running.
    if Sprite.service_status(sprite, Sprite.postgres_service()) == nil do
      Sprite.sh!(sprite, "sudo pg_ctlcluster #{version} main stop >/dev/null 2>&1 || true")
    end

    Sprite.ensure_service!(sprite, Sprite.postgres_service(), postgres_flags(version))

    Sprite.sh!(sprite, """
    set -euo pipefail
    for _ in $(seq 1 30); do pg_isready -q -h 127.0.0.1 && break; sleep 1; done
    pg_isready -q -h 127.0.0.1
    sudo -u postgres psql -qtc "ALTER USER postgres PASSWORD 'postgres'" >/dev/null
    sudo -u postgres psql -qtc "SELECT pg_reload_conf()" >/dev/null
    """)
  end

  defp postgres_flags(version) do
    args = [
      "-u",
      "postgres",
      "/usr/lib/postgresql/#{version}/bin/postgres",
      "-D",
      "/var/lib/postgresql/#{version}/main",
      "-c",
      "config_file=/etc/postgresql/#{version}/main/postgresql.conf"
    ]

    ~s(--cmd /usr/bin/sudo --args "#{Enum.join(args, ",")}")
  end

  defp install_elixir(sprite, version) do
    Sprite.step("Installing Elixir #{version}")

    Sprite.stream!(sprite, """
    set -euo pipefail
    if elixir-version list | grep -q '^ *#{version}-otp-'; then
      echo "already installed"
    else
      elixir-version install #{version}
    fi
    echo "Erlang/OTP $(erl -noshell -eval 'io:format("~s", [erlang:system_info(otp_release)]), halt().') (the sprite's build)"
    """)
  end

  defp install_ssh_key(sprite, {:file, key_path}, origin) do
    Sprite.step("Installing #{key_path}")
    fs = Sprites.filesystem(sprite, Sprite.home())
    name = Path.basename(key_path)
    Filesystem.write!(fs, ".ssh/#{name}", File.read!(key_path), mode: 0o600)

    if File.regular?(key_path <> ".pub") do
      Filesystem.write!(fs, ".ssh/#{name}.pub", File.read!(key_path <> ".pub"), mode: 0o644)
    end

    configure_ssh(sprite, origin, name)
  end

  defp install_ssh_key(sprite, {:deploy_key, repo}, origin) do
    Sprite.step("Registering a deploy key for #{repo}")
    title = Sprite.deploy_key_title(sprite.name)

    public_key =
      Sprite.sh!(
        sprite,
        """
        set -euo pipefail
        mkdir -p ~/.ssh && chmod 700 ~/.ssh
        [ -f ~/#{@sprite_key} ] || ssh-keygen -q -t ed25519 -N "" -C "$TITLE" -f ~/#{@sprite_key}
        cat ~/#{@sprite_key}.pub
        """,
        env: [{"TITLE", title}]
      )

    if title in deploy_key_titles!(repo) do
      Sprite.info("Deploy key #{inspect(title)} already registered")
    else
      key_file = Path.join(System.tmp_dir!(), "#{sprite.name}-deploy-key.pub")
      File.write!(key_file, public_key <> "\n")

      try do
        Sprite.gh!([
          "repo",
          "deploy-key",
          "add",
          key_file,
          "--repo",
          repo,
          "--allow-write",
          "--title",
          title
        ])
      after
        File.rm(key_file)
      end
    end

    configure_ssh(sprite, origin, Path.basename(@sprite_key))
  end

  defp deploy_key_titles!(repo) do
    case Sprite.deploy_keys(repo) do
      {:ok, keys} -> Enum.map(keys, fn {_id, title} -> title end)
      {:error, out} -> Mix.raise("Could not list the deploy keys of #{repo}:\n#{out}")
    end
  end

  defp configure_ssh(sprite, origin, key_name) do
    case Sprite.ssh_host(origin) do
      nil ->
        Sprite.info("#{origin} is not an SSH remote; leaving ssh config alone")

      host ->
        Sprite.sh!(
          sprite,
          """
          set -euo pipefail
          chmod 700 ~/.ssh
          touch ~/.ssh/known_hosts ~/.ssh/config
          chmod 600 ~/.ssh/known_hosts ~/.ssh/config
          ssh-keygen -F "$HOST" >/dev/null || ssh-keyscan -H "$HOST" >> ~/.ssh/known_hosts 2>/dev/null
          grep -q "^Host $HOST$" ~/.ssh/config ||
            printf 'Host %s\\n  IdentityFile ~/.ssh/%s\\n  IdentitiesOnly yes\\n' "$HOST" "$KEY" >> ~/.ssh/config
          """,
          env: [{"HOST", host}, {"KEY", key_name}]
        )
    end
  end

  defp configure_git(sprite) do
    name = Sprite.git_config("user.name")
    email = Sprite.git_config("user.email")

    if name && email do
      Sprite.step("Configuring git as #{name} <#{email}>")

      Sprite.sh!(
        sprite,
        ~s(git config --global user.name "$NAME" && git config --global user.email "$EMAIL"),
        env: [{"NAME", name}, {"EMAIL", email}]
      )
    end
  end

  defp clone_repo(sprite, origin, branch, dest) do
    Sprite.step("Cloning #{origin} (#{branch}) into #{dest}")

    Sprite.stream!(
      sprite,
      """
      set -euo pipefail
      if [ -d "$DEST/.git" ]; then
        echo "already cloned"
        exit 0
      fi
      git clone "$URL" "$DEST"
      cd "$DEST"
      git checkout "$BRANCH" || echo "Branch $BRANCH is not on origin; staying on the default branch"
      """,
      env: [{"URL", origin}, {"DEST", dest}, {"BRANCH", branch}]
    )
  end

  # First time only: once the app is built, the running `phoenix` service owns
  # `_build` and port 4000, so a second `mix setup` would race its compiler and
  # fail to boot for the seeds. Later dependency changes are applied from a
  # console (`mix setup` there) as they would be locally.
  defp setup_app(sprite, dest) do
    Sprite.step("Running mix setup (a few minutes the first time)")
    app = Mix.Project.config()[:app]

    Sprite.stream!(
      sprite,
      """
      set -euo pipefail
      cd "$DEST"
      if [ -d "_build/dev/lib/$APP" ]; then
        echo "already set up (run mix setup from a console after dependency changes)"
        exit 0
      fi
      mix local.hex --force --if-missing
      mix local.rebar --force --if-missing
      mix setup
      """,
      env: [{"DEST", dest}, {"APP", Atom.to_string(app)}]
    )
  end

  defp ensure_phoenix(sprite, dest) do
    Sprite.step("Configuring the Phoenix service")

    flags =
      ~s(--cmd /.sprite/bin/mix --args phx.server --dir "#{dest}" ) <>
        "--needs #{Sprite.postgres_service()} --http-port #{Sprite.http_port()}"

    Sprite.ensure_service!(sprite, Sprite.phoenix_service(), flags)
  end

  defp summary(sprite) do
    Mix.shell().info("""

    Sprite #{sprite.name} is ready.

      App:         #{Sprite.url(sprite)}
                   (org members only; `sprite url update --auth public -s #{sprite.name}` opens it up)
      Console:     mix sprite.connect
      Claude:      mix sprite.connect -- claude   then /login (not signed in yet)
      Sync:        mix sprite.sync (latest origin default branch, app restarted)
      Services:    mix sprite.stop, then mix sprite.up to bring them back
      Checkpoints: mix sprite.checkpoint list | create | restore ID
      Destroy:     mix sprite.down
    """)
  end
end
