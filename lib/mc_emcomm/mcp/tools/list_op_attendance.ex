defmodule McEmcomm.MCP.Tools.ListOpAttendance do
  @moduledoc false
  use McEmcomm.MCP.Tool

  alias McEmcomm.MCP.Tool
  alias McEmcomm.MCP.Tools.Present
  alias McEmcomm.OAuth.Scopes
  alias McEmcomm.Operations

  @impl true
  def name, do: "list_op_attendance"
  @impl true
  def title, do: "List operation attendance"

  @impl true
  def description,
    do:
      "Lists who attended an operation and how it was recorded (manual, QR asset check-in, or admin)."

  @impl true
  def input_schema do
    Schemas.object(
      %{"operation_id" => Schemas.id("Operation id."), "cursor" => Schemas.cursor()},
      ["operation_id"]
    )
  end

  @impl true
  def output_schema, do: Schemas.page(Schemas.attendance(), "attendance")
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
      |> Operations.list_attendance()
      |> Enum.sort_by(& &1.recorded_at, {:asc, DateTime})
      |> page(args["cursor"], "attendance", &Present.attendance/1)
    end
  end
end
