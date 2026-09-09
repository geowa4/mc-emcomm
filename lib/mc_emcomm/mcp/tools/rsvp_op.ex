defmodule McEmcomm.MCP.Tools.RsvpOp do
  @moduledoc false
  use McEmcomm.MCP.Tool

  alias McEmcomm.MCP.Tool
  alias McEmcomm.MCP.Tools.Present
  alias McEmcomm.OAuth.Scopes
  alias McEmcomm.Operations
  alias McEmcomm.Operations.OperationRsvp

  @impl true
  def name, do: "rsvp_op"
  @impl true
  def title, do: "RSVP to an operation"

  @impl true
  def description,
    do:
      "Records or replaces your RSVP to an operation (yes, maybe, or no) with an optional " <>
        "note, exactly as the RSVP form on the operation page does. Requires an approved " <>
        "member profile; RSVPs close once the operation has ended. This is intent to " <>
        "attend, not attendance: use mark_op_attendance once you are actually there."

  @impl true
  def input_schema do
    Schemas.object(
      %{
        "operation_id" => Schemas.id("Operation id."),
        "response" => Schemas.rsvp_response(),
        "note" =>
          Schemas.string("Optional note for the organizers, such as an arrival time.",
            max: OperationRsvp.note_max_length()
          )
      },
      ["operation_id", "response"]
    )
  end

  @impl true
  def output_schema, do: Schemas.rsvp()
  @impl true
  def annotations, do: Tool.write(idempotent: true)
  @impl true
  def required_scope, do: Scopes.operations()
  @impl true
  def required_role, do: :member

  @impl true
  def run(args, context) do
    with {:ok, member} <- approved_member(context),
         {:ok, op} <- fetch(args["operation_id"], &Operations.get_operation/1, "Operation"),
         {:ok, rsvp} <- Operations.rsvp(op, member.id, take_attrs(args, ~w(response note))) do
      {:ok, Present.rsvp(%{rsvp | member: member})}
    end
  end
end
