defmodule McEmcomm.RetentionScrubber do
  @moduledoc """
  Periodic retention task for raw sighting telemetry (§20, §21). A supervised
  GenServer on a timer — explicitly NOT Oban or any other background job
  framework, per the spec's non-goals.

  Every `@interval_ms` it scrubs sightings whose `visited_at` is older than
  `MC_EMCOMM_SIGHTING_RAW_RETENTION_DAYS` days, nulling raw identity/visit
  and geolocation columns and setting `scrubbed_at` (see
  `McEmcomm.Sightings.scrub_before/1`).
  """

  use GenServer

  require Logger

  @interval_ms :timer.hours(1)

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
  end

  @impl true
  def init(opts) do
    interval = Keyword.get(opts, :interval_ms, @interval_ms)
    schedule(interval)
    {:ok, %{interval_ms: interval}}
  end

  @impl true
  def handle_info(:scrub, state) do
    run_scrub()
    schedule(state.interval_ms)
    {:noreply, state}
  end

  defp schedule(interval_ms), do: Process.send_after(self(), :scrub, interval_ms)

  defp run_scrub do
    retention_days = Application.fetch_env!(:mc_emcomm, :sighting_raw_retention_days)
    cutoff = DateTime.add(DateTime.utc_now(), -retention_days, :day)

    Logger.info("Scrubbing sighting telemetry visited before #{DateTime.to_iso8601(cutoff)}")
    McEmcomm.Sightings.scrub_before(cutoff)
  end
end
