defmodule McEmcomm.Health.ProbeFailureTest do
  # `async: true` keeps the sandbox in non-shared mode, so a process that was
  # never granted access cannot reach the repo. That is the failure the probe
  # has to absorb rather than crash on.
  use McEmcomm.DataCase, async: true

  alias McEmcomm.Health.Probe

  test "check/0 is false when the database cannot be reached" do
    parent = self()

    # `spawn/1` rather than `Task` so `$callers` does not carry the sandbox
    # allowance across.
    spawn(fn -> send(parent, {:checked, Probe.check()}) end)

    # Generous timeout: under host load (e.g. the emulated amd64 Postgres
    # container) the spawned process can take well over the default 100ms to
    # be scheduled. A wrong `{:checked, true}` still fails the match.
    assert_receive {:checked, false}, 2_000
  end
end
