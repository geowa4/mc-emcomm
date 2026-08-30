defmodule MyApp.Health.ProbeFailureTest do
  # `async: true` keeps the sandbox in non-shared mode, so a process that was
  # never granted access cannot reach the repo. That is the failure the probe
  # has to absorb rather than crash on.
  use MyApp.DataCase, async: true

  alias MyApp.Health.Probe

  test "check/0 is false when the database cannot be reached" do
    parent = self()

    # `spawn/1` rather than `Task` so `$callers` does not carry the sandbox
    # allowance across.
    spawn(fn -> send(parent, {:checked, Probe.check()}) end)

    assert_receive {:checked, false}
  end
end
