defmodule McEmcomm.MCP.Tools.UpdateAsset do
  @moduledoc false
  use McEmcomm.MCP.Tool

  alias McEmcomm.Assets
  alias McEmcomm.MCP.Tool
  alias McEmcomm.MCP.Tools.Present
  alias McEmcomm.OAuth.Scopes

  @impl true
  def name, do: "update_asset"
  @impl true
  def title, do: "Update an asset"

  @impl true
  def description,
    do:
      "Renames, describes, or retires/reactivates an inventory asset (administrators only). Only the fields given change."

  @impl true
  def input_schema do
    Schemas.object(
      %{
        "asset_id" => Schemas.id("Asset id."),
        "name" => Schemas.string("Name.", min: 1, max: 200),
        "description" => Schemas.string("Description.", max: 5000),
        "active" =>
          Schemas.boolean("False retires the asset; its QR page stops recording sightings.")
      },
      ["asset_id"]
    )
  end

  @impl true
  def output_schema, do: Schemas.asset()
  @impl true
  def annotations, do: Tool.write(idempotent: true)
  @impl true
  def required_scope, do: Scopes.membership()
  @impl true
  def required_role, do: :admin

  @impl true
  def run(args, _context) do
    with {:ok, asset} <- fetch(args["asset_id"], &Assets.get_asset/1, "Asset"),
         {:ok, updated} <-
           Assets.update_asset(asset, take_attrs(args, ~w(name description active))) do
      {:ok, Present.asset(updated)}
    end
  end
end
