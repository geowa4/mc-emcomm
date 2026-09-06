defmodule McEmcomm.MCP.Tools.ListNetCheckins do
  @moduledoc false
  use McEmcomm.MCP.Tool

  alias McEmcomm.MCP.Tool
  alias McEmcomm.MCP.Tools.Present
  alias McEmcomm.Net
  alias McEmcomm.OAuth.Scopes

  @impl true
  def name, do: "list_net_checkins"
  @impl true
  def title, do: "List a net's check-ins"

  @impl true
  def description,
    do:
      "Returns a net (on the air or past) with its check-ins in the order they were " <>
        "recorded. Each stint on the net is its own check-in with recorded_at and ended_at."

  @impl true
  def input_schema do
    Schemas.object(%{"net_id" => Schemas.id("Net id."), "cursor" => Schemas.cursor()}, ["net_id"])
  end

  @impl true
  def output_schema do
    page = Schemas.page(Schemas.checkin(), "checkins")

    %{
      page
      | "properties" => Map.put(page["properties"], "net", Schemas.net()),
        "required" => ["net" | page["required"]]
    }
  end

  @impl true
  def annotations, do: Tool.read_only()
  @impl true
  def required_scope, do: Scopes.member()
  @impl true
  def required_role, do: :member

  @impl true
  def run(args, _context) do
    with {:ok, session} <- fetch(args["net_id"], &Net.get_session/1, "Net"),
         checkins = Enum.sort(session.checkins, &earlier?/2),
         {:ok, result} <- page(checkins, args["cursor"], "checkins", &Present.checkin/1) do
      {:ok, Map.put(result, "net", Present.net(session))}
    end
  end

  # Chronological, ties broken by id; DateTime structs must not be compared
  # with the term-order operators.
  defp earlier?(a, b) do
    case DateTime.compare(a.recorded_at, b.recorded_at) do
      :lt -> true
      :gt -> false
      :eq -> a.id <= b.id
    end
  end
end
