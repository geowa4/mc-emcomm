defmodule McEmcomm.MCP.Tools.StartNet do
  @moduledoc false
  use McEmcomm.MCP.Tool

  alias McEmcomm.MCP.Tool
  alias McEmcomm.MCP.Tools.Present
  alias McEmcomm.Net
  alias McEmcomm.OAuth.Scopes

  @impl true
  def name, do: "start_net"
  @impl true
  def title, do: "Start a net"

  @impl true
  def description,
    do:
      "Starts a new net with you as net control and, if you have a call sign, as its " <>
        "first check-in. Requires an approved member profile. The APRS keyword must be a " <>
        "single word unique among nets on the air."

  @impl true
  def input_schema do
    Schemas.object(
      %{
        "name" => Schemas.string("Net name; defaults to today's date.", max: 160),
        "aprs_keyword" =>
          Schemas.string(
            "Word stations beacon in an APRS comment to check in (2–32 chars, no spaces).",
            min: 2,
            max: 32
          ),
        "operation_id" => Schemas.id("Operation to assign the net to (optional).")
      },
      ["aprs_keyword"]
    )
  end

  @impl true
  def output_schema, do: Schemas.net()
  @impl true
  def annotations, do: Tool.write()
  @impl true
  def required_scope, do: Scopes.member()
  @impl true
  def required_role, do: :member

  @impl true
  def run(args, context) do
    with {:ok, member} <- approved_member(context),
         {:ok, session} <-
           Net.start_session(member, %{
             "name" => args["name"],
             "aprs_keyword" => args["aprs_keyword"],
             "operation_id" => args["operation_id"]
           }) do
      {:ok, Present.net(session)}
    end
  end
end
