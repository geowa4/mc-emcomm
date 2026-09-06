defmodule McEmcomm.MCP.Tools.UpdateOp do
  @moduledoc false
  use McEmcomm.MCP.Tool

  alias McEmcomm.MCP.Tool
  alias McEmcomm.MCP.Tools.Present
  alias McEmcomm.OAuth.Scopes
  alias McEmcomm.Operations

  @impl true
  def name, do: "update_op"
  @impl true
  def title, do: "Update an operation"

  @impl true
  def description,
    do:
      "Changes an operation's title, description, window, or visibility (administrators only). Only the fields given change."

  @impl true
  def input_schema do
    Schemas.object(
      %{
        "operation_id" => Schemas.id("Operation id."),
        "title" => Schemas.string("Title.", min: 1, max: 200),
        "description" => Schemas.string("Description.", max: 5000),
        "starts_at" => Schemas.datetime("Start, ISO 8601."),
        "ends_at" => Schemas.datetime("End, ISO 8601."),
        "visibility" => Schemas.string("Visibility.", enum: ~w(public members))
      },
      ["operation_id"]
    )
  end

  @impl true
  def output_schema, do: Schemas.operation()
  @impl true
  def annotations, do: Tool.write(idempotent: true)
  @impl true
  def required_scope, do: Scopes.operations()
  @impl true
  def required_role, do: :admin

  @impl true
  def run(args, _context) do
    with {:ok, op} <- fetch(args["operation_id"], &Operations.get_operation/1, "Operation"),
         {:ok, attrs} <- attrs(args),
         {:ok, updated} <- Operations.update_operation(op, attrs) do
      {:ok, Present.operation(Operations.get_operation!(updated.id))}
    end
  end

  defp attrs(args) do
    base = take_attrs(args, ~w(title description visibility))

    with {:ok, base} <- put_datetime(base, args, "starts_at") do
      put_datetime(base, args, "ends_at")
    end
  end

  defp put_datetime(attrs, args, field) do
    case args[field] do
      nil ->
        {:ok, attrs}

      value ->
        with {:ok, dt} <- parse_datetime(value, field), do: {:ok, Map.put(attrs, field, dt)}
    end
  end
end
