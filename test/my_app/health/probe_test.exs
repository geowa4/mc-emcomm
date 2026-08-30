defmodule MyApp.Health.ProbeTest do
  # Drives the shared probe process and the global readiness flag.
  use MyApp.DataCase, async: false

  alias MyApp.Health.Probe

  @key {Probe, :ready?}

  setup do
    original = :persistent_term.get(@key, false)
    on_exit(fn -> :persistent_term.put(@key, original) end)
    :ok
  end

  test "ready?/0 is false until a probe has succeeded" do
    :persistent_term.erase(@key)
    refute Probe.ready?()
  end

  test "a probe cycle caches its result for ready?/0 to serve" do
    :persistent_term.put(@key, false)

    # The running probe is the one the readiness endpoint reports on, so drive
    # it rather than a stand-in. `async: false` puts the sandbox in shared
    # mode, which is what lets it reach the repo.
    send(Probe, :probe)
    _ = :sys.get_state(Probe)

    assert Probe.ready?()
  end

  test "check/0 is true when the database answers" do
    assert Probe.check()
  end
end
