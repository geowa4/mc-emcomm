defmodule McEmcomm.MCP.Tools.ApproveMember do
  @moduledoc false
  use McEmcomm.MCP.Tool

  alias McEmcomm.MCP.Tool
  alias McEmcomm.MCP.Tools.Present
  alias McEmcomm.Members
  alias McEmcomm.OAuth.Scopes

  @impl true
  def name, do: "approve_member"
  @impl true
  def title, do: "Approve a member"

  @impl true
  def description,
    do:
      "Approves a pending (or reactivates an inactive) member, writing the audit trail " <>
        "(administrators only). Use transition_member for rejections and deactivations."

  @impl true
  def input_schema, do: Schemas.object(%{"member_id" => Schemas.id("Member id.")}, ["member_id"])
  @impl true
  def output_schema, do: Schemas.member_summary()
  @impl true
  def annotations, do: Tool.write()
  @impl true
  def required_scope, do: Scopes.membership()
  @impl true
  def required_role, do: :admin

  @impl true
  def run(args, context) do
    with {:ok, member} <- fetch(args["member_id"], &Members.get_member/1, "Member"),
         {:ok, approved} <- Members.transition_status(member, :approved, context.scope.user) do
      {:ok, Present.member_summary(Members.get_member(approved.id))}
    end
  end
end
