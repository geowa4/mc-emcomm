defmodule McEmcomm.RetentionScrubberTest do
  use McEmcomm.DataCase, async: true

  alias McEmcomm.RetentionScrubber

  test "starts, and running a scrub cycle does not crash" do
    {:ok, pid} = RetentionScrubber.start_link(interval_ms: :timer.hours(24))
    Ecto.Adapters.SQL.Sandbox.allow(McEmcomm.Repo, self(), pid)

    send(pid, :scrub)
    Process.sleep(50)
    assert Process.alive?(pid)
  end
end
