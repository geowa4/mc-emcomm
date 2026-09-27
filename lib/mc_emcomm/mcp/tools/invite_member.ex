defmodule McEmcomm.MCP.Tools.InviteMember do
  @moduledoc false
  use McEmcomm.MCP.Tool

  alias McEmcomm.MCP.Tool
  alias McEmcomm.MCP.Tools.Present
  alias McEmcomm.Members
  alias McEmcomm.OAuth.Scopes

  @impl true
  def name, do: "invite_member"
  @impl true
  def title, do: "Invite a member"

  @impl true
  def description,
    do:
      "Invites a member by email (administrators only): creates their account with an " <>
        "already-approved profile, writes the audit trail, and emails them how to log in. " <>
        "If the address belongs to a pending member, that member is approved instead and " <>
        "keeps their own name and call sign. Refused for any other existing account."

  @impl true
  def input_schema do
    Schemas.object(
      %{
        "email" => Schemas.string("The invitee's email address.", min: 3, max: 160),
        "name" => Schemas.string("The invitee's full name.", min: 1, max: 255),
        "call_sign" => Schemas.string("Amateur radio call sign, if known.", max: 16)
      },
      ["email", "name"]
    )
  end

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
    attrs = take_attrs(args, ~w(email name call_sign))

    with {:ok, member} <- Members.invite_member(attrs, context.scope.user) do
      {:ok, Present.member_summary(Members.get_member(member.id))}
    end
  end
end
