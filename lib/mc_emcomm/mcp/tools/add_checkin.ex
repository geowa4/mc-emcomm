defmodule McEmcomm.MCP.Tools.AddCheckin do
  @moduledoc false
  use McEmcomm.MCP.Tool

  alias McEmcomm.Locations
  alias McEmcomm.MCP.Tool
  alias McEmcomm.MCP.Tools.Present
  alias McEmcomm.Net
  alias McEmcomm.OAuth.Scopes

  @impl true
  def name, do: "add_checkin"
  @impl true
  def title, do: "Add a net check-in"

  @impl true
  def description,
    do:
      "Logs a station checking into a net that is on the air. The call sign is matched to " <>
        "a member when one has it. `location` is \"qth\" (the matched member's home, the " <>
        "default), \"none\", the name of a catalog location from list_locations, or the " <>
        "name of one of the net's operation locations. Pass the same idempotency_key when " <>
        "retrying so the station is logged once."

  @impl true
  def input_schema do
    Schemas.object(
      %{
        "net_id" => Schemas.id("Net id from list_active_nets or start_net."),
        "call_sign" => Schemas.string("Station call sign.", min: 1, max: 16),
        "location" =>
          Schemas.string(
            ~s(Either "qth", "none", a catalog location name, or an operation location name.),
            max: 160
          ),
        "notes" => Schemas.string("Operator notes.", max: 1000),
        "idempotency_key" =>
          Schemas.string("Client-chosen key that makes this call safe to retry.",
            min: 1,
            max: 128
          )
      },
      ["net_id", "call_sign"]
    )
  end

  @impl true
  def output_schema, do: Schemas.checkin()
  @impl true
  def annotations, do: Tool.write(idempotent: true)
  @impl true
  def required_scope, do: Scopes.member()
  @impl true
  def required_role, do: :member

  @impl true
  def run(args, context) do
    with {:ok, _member} <- approved_member(context),
         {:ok, session} <- fetch(args["net_id"], &Net.get_session/1, "Net"),
         :ok <- on_air(session),
         {:ok, location_ref} <- location_ref(args["location"], session),
         {:ok, checkin} <-
           Net.check_in(session, %{
             "call_sign" => args["call_sign"],
             "notes" => args["notes"],
             "location_ref" => location_ref,
             "idempotency_key" => args["idempotency_key"]
           }) do
      {:ok, Present.checkin(checkin)}
    end
  end

  defp on_air(%{ended_at: nil}), do: :ok

  defp on_air(session),
    do:
      {:error,
       "Net #{session.id} ended at #{Present.datetime(session.ended_at)}; start a new net first."}

  defp location_ref(nil, _session), do: {:ok, "qth"}
  defp location_ref("", _session), do: {:ok, "qth"}
  defp location_ref(name, _session) when name in ["qth", "none"], do: {:ok, name}

  defp location_ref(name, session) do
    wanted = String.downcase(String.trim(name))
    catalog = Locations.list_default_locations()
    operation_locations = if session.operation, do: session.operation.locations, else: []

    cond do
      match = Enum.find(catalog, &(String.downcase(&1.name) == wanted)) ->
        {:ok, "default:#{match.id}"}

      match = Enum.find(operation_locations, &(String.downcase(&1.name) == wanted)) ->
        {:ok, "op:#{match.id}"}

      true ->
        names = Enum.map(catalog, & &1.name) ++ Enum.map(operation_locations, & &1.name)

        {:error,
         ~s(Unknown location #{inspect(name)}. Use "qth", "none", or one of: ) <>
           Enum.map_join(names, ", ", &inspect/1) <> "."}
    end
  end
end
