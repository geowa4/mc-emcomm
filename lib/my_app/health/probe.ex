defmodule MyApp.Health.Probe do
  @moduledoc """
  Periodically probes the database and caches the result in `:persistent_term`
  so that `GET /healthz/ready` answers without touching the connection pool.
  """
  use GenServer

  @key {__MODULE__, :ready?}
  @interval 10_000

  def start_link(_), do: GenServer.start_link(__MODULE__, :ok, name: __MODULE__)

  @doc "Cached readiness; `false` until the first successful probe."
  @spec ready?() :: boolean()
  def ready?, do: :persistent_term.get(@key, false)

  @doc "Runs the readiness check now (a `SELECT 1` against the repo)."
  @spec check() :: boolean()
  def check do
    case Ecto.Adapters.SQL.query(MyApp.Repo, "SELECT 1", []) do
      {:ok, _} -> true
      _ -> false
    end
  rescue
    _ -> false
  catch
    :exit, _ -> false
  end

  @impl true
  def init(:ok) do
    :persistent_term.put(@key, false)
    {:ok, %{}, {:continue, :probe}}
  end

  @impl true
  def handle_continue(:probe, state) do
    probe()
    schedule()
    {:noreply, state}
  end

  @impl true
  def handle_info(:probe, state) do
    probe()
    schedule()
    {:noreply, state}
  end

  defp schedule, do: Process.send_after(self(), :probe, @interval)

  defp probe, do: :persistent_term.put(@key, check())
end
