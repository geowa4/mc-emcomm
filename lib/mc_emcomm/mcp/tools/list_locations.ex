defmodule McEmcomm.MCP.Tools.ListLocations do
  @moduledoc false
  use McEmcomm.MCP.Tool

  alias McEmcomm.Locations
  alias McEmcomm.MCP.Tool
  alias McEmcomm.MCP.Tools.Present
  alias McEmcomm.OAuth.Scopes

  @impl true
  def name, do: "list_locations"
  @impl true
  def title, do: "List catalog locations"

  @impl true
  def description,
    do:
      "Lists the named rally-point locations offered as net check-in locations, in display order."

  @impl true
  def input_schema, do: Schemas.object(%{"cursor" => Schemas.cursor()})
  @impl true
  def output_schema, do: Schemas.page(Schemas.location(), "locations")
  @impl true
  def annotations, do: Tool.read_only()
  @impl true
  def required_scope, do: Scopes.member()
  @impl true
  def required_role, do: :member

  @impl true
  def run(args, _context) do
    page(Locations.list_default_locations(), args["cursor"], "locations", &Present.location/1)
  end
end
