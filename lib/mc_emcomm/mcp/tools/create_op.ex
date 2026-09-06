defmodule McEmcomm.MCP.Tools.CreateOp do
  @moduledoc false
  use McEmcomm.MCP.Tool

  alias McEmcomm.MCP.Tool
  alias McEmcomm.MCP.Tools.Present
  alias McEmcomm.OAuth.Scopes
  alias McEmcomm.Operations

  @impl true
  def name, do: "create_op"
  @impl true
  def title, do: "Create an operation"

  @impl true
  def description,
    do:
      "Creates an operation with one or more geofenced locations (administrators only). " <>
        "Every location needs a name unless there is exactly one, which is then called " <>
        "\"Primary Site\"."

  @impl true
  def input_schema do
    Schemas.object(
      %{
        "title" => Schemas.string("Title.", min: 1, max: 200),
        "description" => Schemas.string("Description.", max: 5000),
        "starts_at" => Schemas.datetime("Start, ISO 8601 with offset."),
        "ends_at" => Schemas.datetime("End, ISO 8601 with offset; after starts_at."),
        "visibility" =>
          Schemas.string("public shows on the public site; members is the default.",
            enum: ~w(public members)
          ),
        "locations" =>
          Schemas.array(
            Schemas.object(
              %{
                "name" => Schemas.string("Location name.", max: 160),
                "location" => Schemas.point(),
                "geofence_radius_m" => %{
                  "type" => "integer",
                  "minimum" => 1,
                  "description" => "Radius in meters (default 500)."
                },
                "notes" => Schemas.string("Notes.", max: 1000)
              },
              ["location"]
            ),
            "At least one location."
          )
      },
      ["title", "starts_at", "ends_at", "locations"]
    )
  end

  @impl true
  def output_schema, do: Schemas.operation()
  @impl true
  def annotations, do: Tool.write()
  @impl true
  def required_scope, do: Scopes.operations()
  @impl true
  def required_role, do: :admin

  @impl true
  def run(args, context) do
    with {:ok, starts_at} <- parse_datetime(args["starts_at"], "starts_at"),
         {:ok, ends_at} <- parse_datetime(args["ends_at"], "ends_at"),
         :ok <- at_least_one(args["locations"]) do
      attrs = %{
        "title" => args["title"],
        "description" => args["description"],
        "starts_at" => starts_at,
        "ends_at" => ends_at,
        "visibility" => args["visibility"] || "members",
        "created_by_id" => context.scope.user.id
      }

      locations =
        args["locations"]
        |> Enum.with_index()
        |> Enum.map(fn {loc, index} ->
          %{
            "name" => loc["name"],
            "point" => to_point(loc["location"]),
            "geofence_radius_m" => loc["geofence_radius_m"] || 500,
            "notes" => loc["notes"],
            "position" => index
          }
        end)

      case Operations.create_operation_with_locations(attrs, locations) do
        {:ok, op} -> {:ok, Present.operation(Operations.get_operation!(op.id))}
        {:error, changeset} -> {:error, changeset}
      end
    end
  end

  defp at_least_one([_ | _]), do: :ok
  defp at_least_one(_locations), do: {:error, "locations must contain at least one location."}
end
