defmodule McEmcomm.MCP.Tools.ListCatalog do
  @moduledoc false
  use McEmcomm.MCP.Tool

  alias McEmcomm.MCP.Tool
  alias McEmcomm.MCP.Tools.Catalogs
  alias McEmcomm.MCP.Tools.Present
  alias McEmcomm.OAuth.Scopes

  @impl true
  def name, do: "list_catalog"
  @impl true
  def title, do: "List a training catalog"

  @impl true
  def description,
    do:
      "Lists the capabilities, courses, or certifications catalog by name. Members see " <>
        "active items; administrators may include inactive ones."

  @impl true
  def input_schema do
    Schemas.object(
      %{
        "kind" => Schemas.string("Which catalog.", enum: Catalogs.kinds()),
        "include_inactive" => Schemas.boolean("Include inactive items (administrators only)."),
        "cursor" => Schemas.cursor()
      },
      ["kind"]
    )
  end

  @impl true
  def output_schema, do: Schemas.page(Schemas.catalog_item(), "items")
  @impl true
  def annotations, do: Tool.read_only()
  @impl true
  def required_scope, do: Scopes.member()
  @impl true
  def required_role, do: :member

  @impl true
  def run(args, context) do
    kind = args["kind"]
    all? = args["include_inactive"] == true and McEmcomm.Accounts.Scope.admin?(context.scope)

    kind
    |> Catalogs.list(active_only: not all?)
    |> page(args["cursor"], "items", &Present.catalog_item(kind, &1))
  end
end
