defmodule McEmcomm.MCP.Tools.ListActiveNets do
  @moduledoc false
  use McEmcomm.MCP.Tool

  alias McEmcomm.MCP.Tool
  alias McEmcomm.MCP.Tools.Present
  alias McEmcomm.Net
  alias McEmcomm.OAuth.Scopes

  @impl true
  def name, do: "list_active_nets"
  @impl true
  def title, do: "List active nets"

  @impl true
  def description,
    do:
      "Lists the nets currently on the air, newest first. Use a net's id with " <>
        "add_checkin, list_net_checkins, and end_net."

  @impl true
  def input_schema, do: Schemas.object(%{"cursor" => Schemas.cursor()})
  @impl true
  def output_schema, do: Schemas.page(Schemas.net(), "nets")
  @impl true
  def annotations, do: Tool.read_only()
  @impl true
  def required_scope, do: Scopes.member()
  @impl true
  def required_role, do: :member

  @impl true
  def run(args, _context) do
    page(Net.list_active_sessions(), args["cursor"], "nets", &Present.net/1)
  end
end
