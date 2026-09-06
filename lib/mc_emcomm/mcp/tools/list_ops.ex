defmodule McEmcomm.MCP.Tools.ListOps do
  @moduledoc false
  use McEmcomm.MCP.Tool

  alias McEmcomm.MCP.Tool
  alias McEmcomm.MCP.Tools.Present
  alias McEmcomm.OAuth.Scopes
  alias McEmcomm.Operations

  @impl true
  def name, do: "list_ops"
  @impl true
  def title, do: "List operations"

  @impl true
  def description,
    do:
      "Lists operations (exercises, events, activations), newest start first, optionally by visibility."

  @impl true
  def input_schema do
    Schemas.object(%{
      "visibility" => Schemas.string("Filter by visibility.", enum: ~w(public members)),
      "cursor" => Schemas.cursor()
    })
  end

  @impl true
  def output_schema, do: Schemas.page(Schemas.operation_summary(), "operations")
  @impl true
  def annotations, do: Tool.read_only()
  @impl true
  def required_scope, do: Scopes.operations()
  @impl true
  def required_role, do: :member

  @impl true
  def run(args, _context) do
    visibility = args["visibility"] && String.to_existing_atom(args["visibility"])

    Operations.list_operations(visibility: visibility)
    |> page(args["cursor"], "operations", &Present.operation_summary/1)
  end
end
