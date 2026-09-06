defmodule McEmcomm.MCP.Tools.CreateCatalogItem do
  @moduledoc false
  use McEmcomm.MCP.Tool

  alias McEmcomm.MCP.Tool
  alias McEmcomm.MCP.Tools.Catalogs
  alias McEmcomm.MCP.Tools.Present
  alias McEmcomm.OAuth.Scopes

  @impl true
  def name, do: "create_catalog_item"
  @impl true
  def title, do: "Create a catalog item"

  @impl true
  def description,
    do:
      "Adds a capability, course, or certification to its catalog (administrators only). " <>
        "Certifications may name a prerequisite course and whether a Position Task Book is required."

  @impl true
  def input_schema do
    Schemas.object(
      %{
        "kind" => Schemas.string("Which catalog.", enum: Catalogs.kinds()),
        "name" => Schemas.string("Name, unique within the catalog.", min: 1, max: 160),
        "code" => Schemas.string("Short code such as IS-100 or COML.", max: 40),
        "description" => Schemas.string("Description.", max: 2000),
        "prerequisite_course_id" => Schemas.id("Certifications only: required course id."),
        "requires_task_book" =>
          Schemas.boolean("Certifications only: whether a task book is required.")
      },
      ["kind", "name"]
    )
  end

  @impl true
  def output_schema, do: Schemas.catalog_item()
  @impl true
  def annotations, do: Tool.write()
  @impl true
  def required_scope, do: Scopes.membership()
  @impl true
  def required_role, do: :admin

  @impl true
  def run(args, _context) do
    kind = args["kind"]

    with {:ok, item} <- Catalogs.create(kind, take_attrs(args, Catalogs.fields(kind))) do
      {:ok, Present.catalog_item(kind, item)}
    end
  end
end
