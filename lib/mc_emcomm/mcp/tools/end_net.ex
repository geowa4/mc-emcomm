defmodule McEmcomm.MCP.Tools.EndNet do
  @moduledoc false
  use McEmcomm.MCP.Tool

  alias McEmcomm.MCP.Tool
  alias McEmcomm.MCP.Tools.Present
  alias McEmcomm.Net
  alias McEmcomm.OAuth.Scopes

  @impl true
  def name, do: "end_net"
  @impl true
  def title, do: "End a net"

  @impl true
  def description,
    do:
      "Ends a net that is on the air and closes every open check-in at the same instant. " <>
        "Any approved member may end a net, as on the website. Cannot be undone."

  @impl true
  def input_schema, do: Schemas.object(%{"net_id" => Schemas.id("Net id.")}, ["net_id"])
  @impl true
  def output_schema, do: Schemas.net()
  @impl true
  def annotations, do: Tool.write(destructive: true, idempotent: true)
  @impl true
  def required_scope, do: Scopes.member()
  @impl true
  def required_role, do: :member

  @impl true
  def run(args, context) do
    with {:ok, _member} <- approved_member(context),
         {:ok, session} <- fetch(args["net_id"], &Net.get_session/1, "Net"),
         {:ok, ended} <- end_once(session) do
      {:ok, Present.net(ended)}
    end
  end

  # Ending an already-ended net is a no-op, so retries are safe.
  defp end_once(%{ended_at: nil} = session), do: Net.end_session(session)
  defp end_once(session), do: {:ok, session}
end
