defmodule McEmcomm.MCP.Tools.TransitionMember do
  @moduledoc false
  use McEmcomm.MCP.Tool

  alias McEmcomm.MCP.Tool
  alias McEmcomm.MCP.Tools.Present
  alias McEmcomm.Members
  alias McEmcomm.OAuth.Scopes

  @impl true
  def name, do: "transition_member"
  @impl true
  def title, do: "Change a member's status"

  @impl true
  def description,
    do:
      "Moves a member through the membership state machine (administrators only): " <>
        "pending→approved or rejected, approved→inactive, inactive→approved, " <>
        "rejected→pending. A reason is required for rejected and inactive. Leaving " <>
        "approved status also vacates the member's leadership positions."

  @impl true
  def input_schema do
    Schemas.object(
      %{
        "member_id" => Schemas.id("Member id."),
        "to_status" =>
          Schemas.string("Target status.", enum: ~w(pending approved rejected inactive)),
        "reason" => Schemas.string("Why; required for rejected and inactive.", max: 2000)
      },
      ["member_id", "to_status"]
    )
  end

  @impl true
  def output_schema, do: Schemas.member_summary()
  @impl true
  def annotations, do: Tool.write(destructive: true)
  @impl true
  def required_scope, do: Scopes.membership()
  @impl true
  def required_role, do: :admin

  @impl true
  def run(args, context) do
    with {:ok, member} <- fetch(args["member_id"], &Members.get_member/1, "Member"),
         {:ok, updated} <-
           Members.transition_status(
             member,
             args["to_status"],
             context.scope.user,
             args["reason"]
           ) do
      {:ok, Present.member_summary(Members.get_member(updated.id))}
    end
  end
end
