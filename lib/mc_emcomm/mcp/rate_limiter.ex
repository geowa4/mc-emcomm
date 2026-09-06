defmodule McEmcomm.MCP.RateLimiter do
  @moduledoc """
  A fixed-window request limiter on `:ets` (SPEC.md §28): one counter per
  `{key, window}` where the window is the current minute. Keys are a token id
  on `/mcp` and a client IP on the OAuth endpoints. The table is owned by
  this process, which also sweeps counters from past windows once a minute.

  The counter is node-local by design — each Fly machine enforces the limit
  for the traffic it sees — so the ceiling scales with the machine count
  during a blue-green overlap. That is acceptable for an abuse brake; it is
  not a quota.
  """
  use GenServer

  @table :mc_emcomm_mcp_rate_limiter
  @window_ms 60_000

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
  end

  @doc """
  Counts one request for `key`. `:ok` while the window's count is at most
  `limit`; otherwise `{:error, retry_after}` in whole seconds until the
  window turns over.
  """
  @spec check(term(), pos_integer(), integer()) :: :ok | {:error, pos_integer()}
  def check(key, limit, now_ms \\ System.system_time(:millisecond)) when limit > 0 do
    window = div(now_ms, @window_ms)
    count = :ets.update_counter(@table, {key, window}, {2, 1}, {{key, window}, 0})

    if count <= limit do
      :ok
    else
      remaining_ms = (window + 1) * @window_ms - now_ms
      {:error, max(1, div(remaining_ms + 999, 1000))}
    end
  end

  @doc "Forgets every counter (tests)."
  @spec reset() :: :ok
  def reset do
    :ets.delete_all_objects(@table)
    :ok
  end

  @impl true
  def init(_opts) do
    :ets.new(@table, [:named_table, :public, :set, write_concurrency: true])
    schedule_sweep()
    {:ok, %{}}
  end

  @impl true
  def handle_info(:sweep, state) do
    current = div(System.system_time(:millisecond), @window_ms)
    :ets.select_delete(@table, [{{{:_, :"$1"}, :_}, [{:<, :"$1", current}], [true]}])
    schedule_sweep()
    {:noreply, state}
  end

  defp schedule_sweep, do: Process.send_after(self(), :sweep, @window_ms)
end
