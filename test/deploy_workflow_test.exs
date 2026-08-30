defmodule McEmcomm.DeployWorkflowTest do
  # A repository lint rather than a unit test: the deploy workflow reads the
  # app name from the FLY_APP repository variable, so `mix mc_emcomm.rename` does
  # not have to rewrite it. This guards against someone hard-coding a
  # placeholder there later, which the rename would silently leave behind.
  use ExUnit.Case, async: true

  @workflow ".github/workflows/deploy.yml"
  @placeholders ~w(McEmcommWeb McEmcomm mc_emcomm mc-emcomm)

  test "the deploy workflow contains no rename placeholders" do
    contents = File.read!(@workflow)

    for token <- @placeholders do
      refute contents =~ token, "#{@workflow} must not contain #{token}"
    end
  end
end
