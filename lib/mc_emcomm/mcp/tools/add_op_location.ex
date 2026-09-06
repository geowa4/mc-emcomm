defmodule McEmcomm.MCP.Tools.AddOpLocation do
  @moduledoc false
  use McEmcomm.MCP.Tool

  alias McEmcomm.MCP.Tool
  alias McEmcomm.MCP.Tools.Present
  alias McEmcomm.OAuth.Scopes
  alias McEmcomm.Operations

  @impl true
  def name, do: "add_op_location"
  @impl true
  def title, do: "Add an operation location"

  @impl true
  def description,
    do:
      "Adds a named geofenced location to an operation (administrators only). Names are unique within an operation."

  @impl true
  def input_schema do
    Schemas.object(
      %{
        "operation_id" => Schemas.id("Operation id."),
        "name" => Schemas.string("Location name.", min: 1, max: 160),
        "location" => Schemas.point(),
        "geofence_radius_m" => %{
          "type" => "integer",
          "minimum" => 1,
          "description" => "Radius in meters (default 500)."
        },
        "notes" => Schemas.string("Notes.", max: 1000)
      },
      ["operation_id", "name", "location"]
    )
  end

  @impl true
  def output_schema, do: Schemas.operation_location()
  @impl true
  def annotations, do: Tool.write()
  @impl true
  def required_scope, do: Scopes.operations()
  @impl true
  def required_role, do: :admin

  @impl true
  def run(args, _context) do
    with {:ok, op} <- fetch(args["operation_id"], &Operations.get_operation/1, "Operation"),
         {:ok, location} <-
           Operations.create_operation_location(%{
             "operation_id" => op.id,
             "name" => args["name"],
             "point" => to_point(args["location"]),
             "geofence_radius_m" => args["geofence_radius_m"] || 500,
             "notes" => args["notes"],
             "position" => length(op.locations)
           }) do
      {:ok, Present.operation_location(location)}
    end
  end
end
