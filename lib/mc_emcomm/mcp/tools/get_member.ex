defmodule McEmcomm.MCP.Tools.GetMember do
  @moduledoc false
  use McEmcomm.MCP.Tool

  alias McEmcomm.MCP.Tool
  alias McEmcomm.MCP.Tools.Present
  alias McEmcomm.Members
  alias McEmcomm.OAuth.Scopes

  @impl true
  def name, do: "get_member"
  @impl true
  def title, do: "Get a member"

  @impl true
  def description,
    do:
      "Returns one member as the admin members page shows them: profile, home location, " <>
        "emergency contact, positions, and the status audit trail (administrators only)."

  @impl true
  def input_schema, do: Schemas.object(%{"member_id" => Schemas.id("Member id.")}, ["member_id"])
  @impl true
  def output_schema, do: Schemas.member()
  @impl true
  def annotations, do: Tool.read_only()
  @impl true
  def required_scope, do: Scopes.membership()
  @impl true
  def required_role, do: :admin

  @impl true
  def run(args, _context) do
    with {:ok, member} <- fetch(args["member_id"], &Members.get_member/1, "Member") do
      {:ok, Present.member(member, Members.list_audit_for_member(member.id))}
    end
  end
end
