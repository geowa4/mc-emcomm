defmodule McEmcomm.MCP.Tools.DeleteOp do
  @moduledoc false
  use McEmcomm.MCP.Tool

  alias McEmcomm.MCP.Tool
  alias McEmcomm.MCP.Tools.Present
  alias McEmcomm.OAuth.Scopes
  alias McEmcomm.Operations

  @impl true
  def name, do: "delete_op"
  @impl true
  def title, do: "Delete an operation"

  @impl true
  def description,
    do:
      "Permanently deletes an operation with its locations, attachment records, and " <>
        "attendance (administrators only). Nets assigned to it are unassigned. Cannot be undone."

  @impl true
  def input_schema,
    do: Schemas.object(%{"operation_id" => Schemas.id("Operation id.")}, ["operation_id"])

  @impl true
  def output_schema, do: Schemas.operation_summary()
  @impl true
  def annotations, do: Tool.write(destructive: true, idempotent: true)
  @impl true
  def required_scope, do: Scopes.operations()
  @impl true
  def required_role, do: :admin

  @impl true
  def run(args, _context) do
    with {:ok, op} <- fetch(args["operation_id"], &Operations.get_operation/1, "Operation"),
         {:ok, deleted} <- Operations.delete_operation(op) do
      {:ok, Present.operation_summary(deleted)}
    end
  end
end
