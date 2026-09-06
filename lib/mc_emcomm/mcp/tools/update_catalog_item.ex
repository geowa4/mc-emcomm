defmodule McEmcomm.MCP.Tools.UpdateCatalogItem do
  @moduledoc false
  use McEmcomm.MCP.Tool

  alias McEmcomm.MCP.Tool
  alias McEmcomm.MCP.Tools.Catalogs
  alias McEmcomm.MCP.Tools.Present
  alias McEmcomm.OAuth.Scopes

  @impl true
  def name, do: "update_catalog_item"
  @impl true
  def title, do: "Update a catalog item"

  @impl true
  def description,
    do:
      "Edits or deactivates a capability, course, or certification (administrators only). Only the fields given change."

  @impl true
  def input_schema do
    Schemas.object(
      %{
        "kind" => Schemas.string("Which catalog.", enum: Catalogs.kinds()),
        "id" => Schemas.id("Item id."),
        "name" => Schemas.string("Name.", min: 1, max: 160),
        "code" => Schemas.string("Short code.", max: 40),
        "description" => Schemas.string("Description.", max: 2000),
        "active" => Schemas.boolean("False hides the item from members' profiles."),
        "prerequisite_course_id" => Schemas.id("Certifications only."),
        "requires_task_book" => Schemas.boolean("Certifications only.")
      },
      ["kind", "id"]
    )
  end

  @impl true
  def output_schema, do: Schemas.catalog_item()
  @impl true
  def annotations, do: Tool.write(idempotent: true)
  @impl true
  def required_scope, do: Scopes.membership()
  @impl true
  def required_role, do: :admin

  @impl true
  def run(args, _context) do
    kind = args["kind"]

    with {:ok, item} <- fetch(args["id"], &Catalogs.get(kind, &1), String.capitalize(kind)),
         {:ok, updated} <- Catalogs.update(kind, item, take_attrs(args, Catalogs.fields(kind))) do
      {:ok, Present.catalog_item(kind, updated)}
    end
  end
end
