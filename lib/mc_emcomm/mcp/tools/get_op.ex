defmodule McEmcomm.MCP.Tools.GetOp do
  @moduledoc false
  use McEmcomm.MCP.Tool

  alias McEmcomm.MCP.Tool
  alias McEmcomm.MCP.Tools.Present
  alias McEmcomm.OAuth.Scopes
  alias McEmcomm.Operations

  @impl true
  def name, do: "get_op"
  @impl true
  def title, do: "Get an operation"

  @impl true
  def description,
    do:
      "Returns one operation with its named geofenced locations, attachment metadata " <>
        "(files are downloaded on the website), and attendance."

  @impl true
  def input_schema,
    do: Schemas.object(%{"operation_id" => Schemas.id("Operation id.")}, ["operation_id"])

  @impl true
  def output_schema, do: Schemas.operation()
  @impl true
  def annotations, do: Tool.read_only()
  @impl true
  def required_scope, do: Scopes.operations()
  @impl true
  def required_role, do: :member

  @impl true
  def run(args, _context) do
    with {:ok, op} <- fetch(args["operation_id"], &Operations.get_operation/1, "Operation") do
      {:ok, Present.operation(op)}
    end
  end
end
