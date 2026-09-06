defmodule McEmcomm.MCP.Tools.RemoveOpLocation do
  @moduledoc false
  use McEmcomm.MCP.Tool

  alias McEmcomm.MCP.Tool
  alias McEmcomm.MCP.Tools.Present
  alias McEmcomm.OAuth.Scopes
  alias McEmcomm.Operations

  @impl true
  def name, do: "remove_op_location"
  @impl true
  def title, do: "Remove an operation location"

  @impl true
  def description,
    do:
      "Removes a location from an operation (administrators only). Sightings that matched it keep their operation link. Cannot be undone."

  @impl true
  def input_schema do
    Schemas.object(
      %{
        "operation_id" => Schemas.id("Operation id."),
        "location_id" => Schemas.id("Location id.")
      },
      ["operation_id", "location_id"]
    )
  end

  @impl true
  def output_schema, do: Schemas.operation_location()
  @impl true
  def annotations, do: Tool.write(destructive: true, idempotent: true)
  @impl true
  def required_scope, do: Scopes.operations()
  @impl true
  def required_role, do: :admin

  @impl true
  def run(args, _context) do
    with {:ok, op} <- fetch(args["operation_id"], &Operations.get_operation/1, "Operation"),
         {:ok, location} <- find_location(op, args["location_id"]),
         {:ok, deleted} <- Operations.delete_operation_location(location) do
      {:ok, Present.operation_location(deleted)}
    end
  end

  defp find_location(op, id) do
    case Enum.find(op.locations, &(&1.id == id)) do
      nil -> {:error, "Operation #{op.id} has no location #{id}."}
      location -> {:ok, location}
    end
  end
end
