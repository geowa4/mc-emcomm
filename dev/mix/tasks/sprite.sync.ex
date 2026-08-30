defmodule Mix.Tasks.Sprite.Sync do
  @shortdoc "Updates the app's Sprite to the latest commit of origin's default branch"

  @moduledoc """
  Brings the repository clone inside the sprite created by `mix sprite.up` up
  to date with origin's default branch, restarts the running app on the new
  code, and takes a checkpoint:

    1. fetches `origin` and rebases the sprite's checked-out branch onto
       origin's default branch (`origin/HEAD`, re-read from the remote). A
       rebase that hits conflicts is aborted and the task fails, leaving the
       branch as it was. The working tree must be clean
    2. if the `phoenix` service is running, stops it, runs `mix deps.get`,
       `mix assets.setup`, `mix compile`, and `mix ecto.migrate`, starts it
       again, and waits until `/healthz/ready` answers. A service that is not
       running is left alone; `mix sprite.up` starts it
    3. takes a checkpoint named after the new commit (skipped when one already
       exists, or with `--no-checkpoint`)

  When the sprite is already at the latest commit nothing is restarted and no
  checkpoint is taken. Requires `SPRITES_TOKEN`; see CONTRIBUTING.md § Sprites.

      mix sprite.sync [--name NAME] [--no-checkpoint]

  ## Options

    * `--name` - sprite name (default: repository name)
    * `--no-checkpoint` - skip the checkpoint
  """
  use Mix.Task

  alias Mix.Sprite

  @switches [checkpoint: :boolean]
  @ready_timeout :timer.minutes(5)

  @impl Mix.Task
  def run(argv) do
    {opts, _args} = Sprite.parse_args(argv, @switches)
    sprite = Sprite.existing_sprite!(opts)
    dest = Path.join(Sprite.home(), Sprite.repo_name(Sprite.origin_url!()))

    before = head(sprite, dest)
    {branch, default} = rebase!(sprite, dest)
    after_ = head(sprite, dest)

    if after_ == before do
      Sprite.info("#{branch} is already up to date with #{default} at #{short(before)}")
    else
      Sprite.info("#{branch} moved from #{short(before)} to #{short(after_)}")
      restart_if_running(sprite, dest)

      if Keyword.get(opts, :checkpoint, true) do
        Sprite.ensure_checkpoint!(sprite, "mix sprite.sync: #{branch} at #{short(after_)}")
      end
    end
  end

  defp head(sprite, dest), do: Sprite.sh!(sprite, ~s(git -C "#{dest}" rev-parse HEAD))

  defp short(sha), do: String.slice(sha, 0, 7)

  # Prints the sprite-side git output and returns `{branch, "origin/<default>"}`.
  defp rebase!(sprite, dest) do
    Sprite.step("Rebasing onto origin's default branch")

    script = """
    set -euo pipefail
    cd "$DEST"
    branch=$(git symbolic-ref -q --short HEAD) ||
      { echo "HEAD is detached; check out a branch first"; exit 1; }
    if [ -n "$(git status --porcelain --untracked-files=no)" ]; then
      echo "The working tree has uncommitted changes; commit or stash them first:"
      git status --short --untracked-files=no
      exit 1
    fi
    git fetch --prune origin
    git remote set-head origin --auto >/dev/null
    default=$(git symbolic-ref -q --short refs/remotes/origin/HEAD)
    if ! git rebase --no-autostash "$default"; then
      git rebase --abort || true
      echo "Rebasing $branch onto $default hit conflicts; the rebase was aborted and $branch is unchanged"
      exit 1
    fi
    echo "SPRITE_SYNC $branch $default"
    """

    case Sprite.sh(sprite, script, env: [{"DEST", dest}]) do
      {out, 0} ->
        {report, [branch, default]} = parse_report(out)
        Enum.each(report, &Sprite.info/1)
        {branch, default}

      {out, _code} ->
        Mix.raise("Could not update #{dest}:\n#{String.trim(out)}")
    end
  end

  defp parse_report(out) do
    lines = out |> String.trim() |> String.split("\n")
    {report, [marker]} = Enum.split(lines, -1)
    {report, marker |> String.trim_leading("SPRITE_SYNC ") |> String.split(" ", parts: 2)}
  end

  ## Restart

  defp restart_if_running(sprite, dest) do
    phoenix = Sprite.phoenix_service()

    if Sprite.service_status(sprite, phoenix) == "running" do
      Sprite.stop_service!(sprite, phoenix)
      prepare(sprite, dest)
      Sprite.start_service!(sprite, phoenix)
      wait_ready(sprite)
    else
      Sprite.info("Service #{phoenix} is not running; `mix sprite.up` starts it")
    end
  end

  # The service owns `_build` while it runs, so this only happens while it is
  # stopped. Compiling here surfaces build errors before the service restarts.
  defp prepare(sprite, dest) do
    Sprite.step("Fetching dependencies, compiling, and migrating")

    Sprite.stream!(
      sprite,
      """
      set -euo pipefail
      cd "$DEST"
      mix deps.get
      mix assets.setup
      mix compile
      mix ecto.migrate
      """,
      env: [{"DEST", dest}]
    )
  end

  defp wait_ready(sprite) do
    phoenix = Sprite.phoenix_service()
    Sprite.step("Waiting for #{phoenix} to become ready on port #{Sprite.http_port()}")

    Sprite.sh!(
      sprite,
      """
      set -uo pipefail
      for _ in $(seq 1 #{div(@ready_timeout, 1000)}); do
        if curl -sf -o /dev/null "http://localhost:$PORT/healthz/ready"; then
          echo "ready"
          exit 0
        fi
        if sprite-env services get "$SERVICE" | grep -q '"status":"failed"'; then
          echo "Service $SERVICE failed to start:"
          tail -n 40 "/.sprite/logs/services/$SERVICE.log"
          exit 1
        fi
        sleep 1
      done
      echo "Service $SERVICE did not become ready in time:"
      tail -n 40 "/.sprite/logs/services/$SERVICE.log"
      exit 1
      """,
      env: [{"PORT", Integer.to_string(Sprite.http_port())}, {"SERVICE", phoenix}],
      timeout: @ready_timeout + :timer.seconds(30)
    )
    |> Sprite.info()
  end
end
