defmodule McEmcommWeb.InventoryLive.Show do
  @moduledoc """
  Asset inventory detail. Admin-only sighting columns (identity/visit,
  client environment, geolocation — spec §7.11) are gated at the query
  layer, not just the template: `Sightings.list_for_asset_member_view/1`
  never selects them, so a member never receives them over the wire.
  """

  use McEmcommWeb, :live_view

  alias McEmcomm.Accounts.Scope
  alias McEmcomm.Assets
  alias McEmcomm.Sightings
  alias McEmcomm.Storage
  alias McEmcommWeb.MapHelpers

  @impl true
  def mount(%{"public_id" => public_id}, _session, socket) do
    case Assets.get_asset_by_public_id(public_id) do
      nil ->
        {:ok,
         socket |> put_flash(:error, "Asset not found.") |> push_navigate(to: ~p"/app/inventory")}

      asset ->
        admin? = Scope.admin?(socket.assigns.current_scope)

        {:ok,
         assign(socket,
           page_title: asset.name,
           asset: asset,
           image_url: asset.image_key && Storage.presign_download_url(asset.image_key),
           admin?: admin?,
           sightings:
             if(admin?,
               do: Sightings.list_for_asset_admin_view(asset.id),
               else: Sightings.list_for_asset_member_view(asset.id)
             ),
           markers_json: if(admin?, do: admin_markers_json(asset.id), else: "[]"),
           tile_url: MapHelpers.tile_url()
         )}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        {@asset.name}
        <:subtitle><span class="font-mono">{@asset.public_id}</span></:subtitle>
        <:actions>
          <.link navigate={~p"/a/#{@asset.public_id}/s"} class="btn btn-outline btn-sm">View sighting page</.link>
        </:actions>
      </.header>

      <img :if={@image_url} src={@image_url} alt={@asset.name} class="rounded-box max-w-sm" />
      <p :if={@asset.description}>{@asset.description}</p>

      <div :if={@admin?}>
        <h2 class="text-lg font-semibold mt-6">Sighting map</h2>
        <div
          id="asset-map"
          phx-hook="LeafletMap"
          phx-update="ignore"
          class="map-canvas"
          data-markers={@markers_json}
          data-tile-url={@tile_url}
        >
        </div>
      </div>

      <h2 class="text-lg font-semibold mt-6">
        {if @admin?, do: "Sighting log", else: "Recent activity"}
      </h2>
      <.table :if={@sightings != []} id="sightings" rows={@sightings}>
        <:col :let={s} label="Call sign">{s.call_sign}</:col>
        <:col :let={s} label="Submitted">
          {s.submitted_at && Calendar.strftime(s.submitted_at, "%Y-%m-%d %H:%M")}
        </:col>
        <:col :let={s} label="Note">{s.note}</:col>
        <:col :let={s} label="Verified">{s.verified}</:col>
        <:col :let={s} :if={@admin?} label="Visited">
          {Calendar.strftime(s.visited_at, "%Y-%m-%d %H:%M")}
        </:col>
        <:col :let={s} :if={@admin?} label="IP">{s.remote_ip}</:col>
        <:col :let={s} :if={@admin?} label="Browser">{s.browser_name}</:col>
      </.table>
      <p :if={@sightings == []} class="text-base-content/70">No sightings recorded yet.</p>
    </Layouts.app>
    """
  end

  defp admin_markers_json(asset_id) do
    asset_id
    |> Sightings.list_for_asset_admin_view()
    |> Enum.filter(&match?(%Geo.Point{}, &1.point))
    |> Enum.map(&%{point: &1.point, title: &1.call_sign || "sighting"})
    |> MapHelpers.markers_json()
  end
end
