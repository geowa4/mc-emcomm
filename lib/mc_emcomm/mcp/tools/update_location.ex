defmodule McEmcomm.MCP.Tools.UpdateLocation do
  @moduledoc false
  use McEmcomm.MCP.Tool

  alias McEmcomm.Locations
  alias McEmcomm.MCP.Tool
  alias McEmcomm.MCP.Tools.Present
  alias McEmcomm.OAuth.Scopes

  @impl true
  def name, do: "update_location"
  @impl true
  def title, do: "Update a catalog location"

  @impl true
  def description,
    do:
      "Renames or moves a catalog location (administrators only). Past check-ins keep their snapshot."

  @impl true
  def input_schema do
    Schemas.object(
      %{
        "location_id" => Schemas.id("Location id."),
        "name" => Schemas.string("Name.", min: 1, max: 160),
        "location" => Schemas.point(),
        "position" => %{"type" => "integer", "minimum" => 0, "description" => "Display order."}
      },
      ["location_id"]
    )
  end

  @impl true
  def output_schema, do: Schemas.location()
  @impl true
  def annotations, do: Tool.write(idempotent: true)
  @impl true
  def required_scope, do: Scopes.membership()
  @impl true
  def required_role, do: :admin

  @impl true
  def run(args, _context) do
    attrs = take_attrs(args, ~w(name position))

    attrs =
      if args["location"], do: Map.put(attrs, "point", to_point(args["location"])), else: attrs

    with {:ok, location} <-
           fetch(args["location_id"], &Locations.get_default_location/1, "Location"),
         {:ok, updated} <- Locations.update_default_location(location, attrs) do
      {:ok, Present.location(updated)}
    end
  end
end
