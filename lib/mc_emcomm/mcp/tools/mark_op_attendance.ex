defmodule McEmcomm.MCP.Tools.MarkOpAttendance do
  @moduledoc false
  use McEmcomm.MCP.Tool

  alias McEmcomm.MCP.Tool
  alias McEmcomm.MCP.Tools.Present
  alias McEmcomm.OAuth.Scopes
  alias McEmcomm.Operations

  @impl true
  def name, do: "mark_op_attendance"
  @impl true
  def title, do: "Mark my attendance"

  @impl true
  def description,
    do:
      "Records that you attended an operation (source \"manual\"), exactly as the " <>
        "\"Mark my attendance\" button does. Requires an approved member profile; " <>
        "recording twice is a no-op."

  @impl true
  def input_schema,
    do: Schemas.object(%{"operation_id" => Schemas.id("Operation id.")}, ["operation_id"])

  @impl true
  def output_schema, do: Schemas.attendance()
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
         {:ok, _} <- Operations.record_attendance(op.id, member.id, :manual) do
      attendance =
        op.id
        |> Operations.list_attendance()
        |> Enum.find(&(&1.member_id == member.id))

      {:ok, Present.attendance(attendance)}
    end
  end
end
