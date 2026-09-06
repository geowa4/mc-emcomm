defmodule McEmcomm.MCP.Tools.ListPendingMembers do
  @moduledoc false
  use McEmcomm.MCP.Tool

  alias McEmcomm.MCP.Tool
  alias McEmcomm.MCP.Tools.Present
  alias McEmcomm.Members
  alias McEmcomm.OAuth.Scopes

  @impl true
  def name, do: "list_pending_members"
  @impl true
  def title, do: "List pending members"

  @impl true
  def description,
    do:
      "Lists members awaiting approval, by name (administrators only). Approve one with approve_member."

  @impl true
  def input_schema, do: Schemas.object(%{"cursor" => Schemas.cursor()})
  @impl true
  def output_schema, do: Schemas.page(Schemas.member_summary(), "members")
  @impl true
  def annotations, do: Tool.read_only()
  @impl true
  def required_scope, do: Scopes.membership()
  @impl true
  def required_role, do: :admin

  @impl true
  def run(args, _context) do
    page(Members.list_pending_members(), args["cursor"], "members", &Present.member_summary/1)
  end
end
