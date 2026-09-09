defmodule McEmcomm.MCP.Tools.ListOpRsvps do
  @moduledoc false
  use McEmcomm.MCP.Tool

  alias McEmcomm.MCP.Tool
  alias McEmcomm.MCP.Tools.Present
  alias McEmcomm.OAuth.Scopes
  alias McEmcomm.Operations

  @impl true
  def name, do: "list_op_rsvps"
  @impl true
  def title, do: "List operation RSVPs"

  @impl true
  def description,
    do:
      "Lists who has RSVP'd to an operation and how (yes, maybe, no), going first. " <>
        "An RSVP is intent to attend; use list_op_attendance for who actually showed up."

  @impl true
  def input_schema do
    Schemas.object(
      %{"operation_id" => Schemas.id("Operation id."), "cursor" => Schemas.cursor()},
      ["operation_id"]
    )
  end

  @impl true
  def output_schema, do: Schemas.page(Schemas.rsvp(), "rsvps")
  @impl true
  def annotations, do: Tool.read_only()
  @impl true
  def required_scope, do: Scopes.operations()
  @impl true
  def required_role, do: :member

  @impl true
  def run(args, _context) do
    with {:ok, op} <- fetch(args["operation_id"], &Operations.get_operation/1, "Operation") do
      op.id
      |> Operations.list_rsvps()
      |> page(args["cursor"], "rsvps", &Present.rsvp/1)
    end
  end
end
