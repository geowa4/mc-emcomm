defmodule McEmcomm.MCP.Tools.ListAssets do
  @moduledoc false
  use McEmcomm.MCP.Tool

  alias McEmcomm.Assets
  alias McEmcomm.MCP.Tool
  alias McEmcomm.MCP.Tools.Present
  alias McEmcomm.OAuth.Scopes

  @impl true
  def name, do: "list_assets"
  @impl true
  def title, do: "List equipment"

  @impl true
  def description,
    do:
      "Lists inventory assets by name. Members see active assets; pass include_inactive as an administrator to see all."

  @impl true
  def input_schema do
    Schemas.object(%{
      "include_inactive" => Schemas.boolean("Include retired assets (administrators only)."),
      "cursor" => Schemas.cursor()
    })
  end

  @impl true
  def output_schema, do: Schemas.page(Schemas.asset(), "assets")
  @impl true
  def annotations, do: Tool.read_only()
  @impl true
  def required_scope, do: Scopes.member()
  @impl true
  def required_role, do: :member

  @impl true
  def run(args, context) do
    all? = args["include_inactive"] == true and McEmcomm.Accounts.Scope.admin?(context.scope)

    Assets.list_assets(active_only: not all?)
    |> page(args["cursor"], "assets", &Present.asset/1)
  end
end
