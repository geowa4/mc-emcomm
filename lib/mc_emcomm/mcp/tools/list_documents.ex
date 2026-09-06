defmodule McEmcomm.MCP.Tools.ListDocuments do
  @moduledoc false
  use McEmcomm.MCP.Tool

  alias McEmcomm.Content
  alias McEmcomm.MCP.Tool
  alias McEmcomm.MCP.Tools.Present
  alias McEmcomm.OAuth.Scopes

  @impl true
  def name, do: "list_documents"
  @impl true
  def title, do: "List resource documents"

  @impl true
  def description,
    do:
      "Lists the published Resources documents, including members-only ones. Files are downloaded from the website."

  @impl true
  def input_schema, do: Schemas.object(%{"cursor" => Schemas.cursor()})
  @impl true
  def output_schema, do: Schemas.page(Schemas.document(), "documents")
  @impl true
  def annotations, do: Tool.read_only()
  @impl true
  def required_scope, do: Scopes.member()
  @impl true
  def required_role, do: :member

  @impl true
  def run(args, _context) do
    Content.list_documents(active_only: true, members_only_allowed: true)
    |> page(args["cursor"], "documents", &Present.document/1)
  end
end
