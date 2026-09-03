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

        # The map defaults to the day the asset was last seen, so a
        # long-lived asset doesn't open onto its entire sighting history.
        map_since = (admin? && Sightings.last_seen_on(asset.id)) || Date.utc_today()

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
           map_mode: "since",
           map_since: map_since,
           markers_json: if(admin?, do: markers_json(asset.id, {:since, map_since}), else: "[]"),
           tile_url: MapHelpers.tile_url()
         )}
    end
  end

  @impl true
  def handle_event("filter_map", params, socket) do
    filter = parse_map_filter(params, socket.assigns.map_since)

    {mode, since} =
      case filter do
        {:since, date} -> {"since", date}
        {:last, n} -> {Integer.to_string(n), socket.assigns.map_since}
      end

    {:noreply,
     assign(socket,
       map_mode: mode,
       map_since: since,
       markers_json: markers_json(socket.assigns.asset.id, filter)
     )}
  end

  defp parse_map_filter(%{"mode" => mode}, _fallback) when mode in ~w(5 10 20),
    do: {:last, String.to_integer(mode)}

  defp parse_map_filter(params, fallback) do
    case Date.from_iso8601(params["since"] || "") do
      {:ok, date} -> {:since, date}
      {:error, _} -> {:since, fallback}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} active_net={@active_net}>
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
        <form id="map-filter" phx-change="filter_map" class="flex flex-wrap items-center gap-2 my-2">
          <label for="map-filter-mode" class="text-sm">Show</label>
          <select id="map-filter-mode" name="mode" class="select select-sm w-auto">
            <option value="since" selected={@map_mode == "since"}>Sightings since</option>
            <option value="5" selected={@map_mode == "5"}>Last 5</option>
            <option value="10" selected={@map_mode == "10"}>Last 10</option>
            <option value="20" selected={@map_mode == "20"}>Last 20</option>
          </select>
          <input
            :if={@map_mode == "since"}
            id="map-filter-since"
            type="date"
            name="since"
            value={@map_since}
            class="input input-sm w-auto"
          />
        </form>
        <.static_map
          id="asset-map"
          label={"Map of sightings of #{@asset.name}"}
          markers_json={@markers_json}
          tile_url={@tile_url}
        />
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

  defp markers_json(asset_id, filter) do
    opts =
      case filter do
        {:since, date} -> [since: date]
        {:last, n} -> [limit: n]
      end

    asset_id
    |> Sightings.list_located_for_asset(opts)
    |> Enum.map(&%{point: &1.point, title: &1.call_sign || "sighting"})
    |> MapHelpers.markers_json()
  end
end
