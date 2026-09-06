defmodule McEmcomm.MCP.Tools.GetAsset do
  @moduledoc false
  use McEmcomm.MCP.Tool

  alias McEmcomm.Assets
  alias McEmcomm.MCP.Tool
  alias McEmcomm.MCP.Tools.Present
  alias McEmcomm.OAuth.Scopes
  alias McEmcomm.Sightings

  @impl true
  def name, do: "get_asset"
  @impl true
  def title, do: "Get an asset"

  @impl true
  def description,
    do:
      "Returns one asset with its recent submitted sightings (call sign, time, note, " <>
        "verified). Raw sighting telemetry is admin-only on the website and is never " <>
        "returned here."

  @impl true
  def input_schema do
    Schemas.object(
      %{
        "asset_id" => Schemas.id("Asset id."),
        "public_id" => Schemas.string("Six-character public id.", max: 6)
      },
      []
    )
  end

  @impl true
  def output_schema do
    asset = Schemas.asset()

    %{
      asset
      | "properties" =>
          Map.put(asset["properties"], "sightings", Schemas.array(Schemas.sighting())),
        "required" => asset["required"] ++ ["sightings"]
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
    with {:ok, asset} <- find(args) do
      sightings = Sightings.list_for_asset_member_view(asset.id)

      {:ok,
       asset |> Present.asset() |> Map.put("sightings", Enum.map(sightings, &Present.sighting/1))}
    end
  end

  defp find(%{"asset_id" => id}), do: fetch(id, &Assets.get_asset/1, "Asset")

  defp find(%{"public_id" => public_id}) when is_binary(public_id) do
    case Assets.get_asset_by_public_id(public_id) do
      nil -> {:error, "No asset has public id #{inspect(public_id)}."}
      asset -> {:ok, asset}
    end
  end

  defp find(_args), do: {:error, "Give asset_id or public_id."}
end
