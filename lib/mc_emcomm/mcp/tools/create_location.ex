defmodule McEmcomm.MCP.Tools.CreateLocation do
  @moduledoc false
  use McEmcomm.MCP.Tool

  alias McEmcomm.Locations
  alias McEmcomm.MCP.Tool
  alias McEmcomm.MCP.Tools.Present
  alias McEmcomm.OAuth.Scopes

  @impl true
  def name, do: "create_location"
  @impl true
  def title, do: "Create a catalog location"

  @impl true
  def description, do: "Adds a named rally-point location to the catalog (administrators only)."

  @impl true
  def input_schema do
    Schemas.object(
      %{
        "name" => Schemas.string("Name, unique in the catalog.", min: 1, max: 160),
        "location" => Schemas.point(),
        "position" => %{
          "type" => "integer",
          "minimum" => 0,
          "description" => "Display order (default 0)."
        }
      },
      ["name", "location"]
    )
  end

  @impl true
  def output_schema, do: Schemas.location()
  @impl true
  def annotations, do: Tool.write()
  @impl true
  def required_scope, do: Scopes.membership()
  @impl true
  def required_role, do: :admin

  @impl true
  def run(args, _context) do
    attrs = %{
      "name" => args["name"],
      "point" => to_point(args["location"]),
      "position" => args["position"] || 0
    }

    with {:ok, location} <- Locations.create_default_location(attrs) do
      {:ok, Present.location(location)}
    end
  end
end
