defmodule McEmcomm.MCP.Tools.ListMembers do
  @moduledoc false
  use McEmcomm.MCP.Tool

  alias McEmcomm.MCP.Tool
  alias McEmcomm.MCP.Tools.Present
  alias McEmcomm.Members
  alias McEmcomm.OAuth.Scopes

  @impl true
  def name, do: "list_members"
  @impl true
  def title, do: "List members"

  @impl true
  def description,
    do: "Lists members by name with status, call sign, and positions (administrators only)."

  @impl true
  def input_schema do
    Schemas.object(%{
      "status" =>
        Schemas.string("Filter by status.", enum: ~w(pending approved rejected inactive)),
      "cursor" => Schemas.cursor()
    })
  end

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
    status = args["status"] && String.to_existing_atom(args["status"])

    page(
      Members.list_members(status: status),
      args["cursor"],
      "members",
      &Present.member_summary/1
    )
  end
end
