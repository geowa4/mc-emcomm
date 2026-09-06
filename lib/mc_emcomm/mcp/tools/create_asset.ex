defmodule McEmcomm.MCP.Tools.CreateAsset do
  @moduledoc false
  use McEmcomm.MCP.Tool

  alias McEmcomm.Assets
  alias McEmcomm.MCP.Tool
  alias McEmcomm.MCP.Tools.Present
  alias McEmcomm.OAuth.Scopes

  @impl true
  def name, do: "create_asset"
  @impl true
  def title, do: "Create an asset"

  @impl true
  def description,
    do:
      "Adds an inventory asset with a generated six-character public id (administrators only). Images are uploaded on the website."

  @impl true
  def input_schema do
    Schemas.object(
      %{
        "name" => Schemas.string("Name.", min: 1, max: 200),
        "description" => Schemas.string("Description.", max: 5000)
      },
      ["name"]
    )
  end

  @impl true
  def output_schema, do: Schemas.asset()
  @impl true
  def annotations, do: Tool.write()
  @impl true
  def required_scope, do: Scopes.membership()
  @impl true
  def required_role, do: :admin

  @impl true
  def run(args, _context) do
    with {:ok, asset} <- Assets.create_asset(take_attrs(args, ~w(name description))) do
      {:ok, Present.asset(asset)}
    end
  end
end
