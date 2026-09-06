defmodule McEmcomm.MCP.RateLimiterTest do
  use ExUnit.Case, async: true

  alias McEmcomm.MCP.RateLimiter

  test "allows `limit` requests per fixed window and then reports the wait" do
    key = {:test, System.unique_integer()}
    now = 120_000

    assert :ok = RateLimiter.check(key, 2, now)
    assert :ok = RateLimiter.check(key, 2, now + 1_000)
    assert {:error, 58} = RateLimiter.check(key, 2, now + 2_000)
    assert {:error, 1} = RateLimiter.check(key, 2, now + 59_500)

    # A new window starts clean.
    assert :ok = RateLimiter.check(key, 2, now + 60_000)
  end

  test "keys are independent" do
    a = {:test, System.unique_integer()}
    b = {:test, System.unique_integer()}
    assert :ok = RateLimiter.check(a, 1)
    assert {:error, _} = RateLimiter.check(a, 1)
    assert :ok = RateLimiter.check(b, 1)
  end
end
