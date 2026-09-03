defmodule McEmcommWeb.AdminLive.DefaultLocationIndex do
  @moduledoc "Admin catalog of default locations selectable at net check-in."

  use McEmcommWeb, :live_view

  alias McEmcomm.Locations
  alias McEmcomm.Locations.DefaultLocation
  alias McEmcommWeb.MapHelpers

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: "Default locations",
       locations: Locations.list_default_locations(),
       editing: nil,
       form: nil,
       pending_point: nil,
       tile_url: MapHelpers.tile_url()
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} active_net={@active_net}>
      <.header>
        Default locations
        <:actions>
          <.button phx-click="new" class="btn btn-primary">New location</.button>
        </:actions>
      </.header>

      <p class="text-sm text-base-content/70">
        Named map points any net control can select as a check-in's location.
      </p>

      <div :if={@form} class="mb-6">
        <.map_picker
          id="default-location-map"
          label="Location map"
          point={pending_point(@pending_point) || (@editing && @editing.point)}
          tile_url={@tile_url}
          instructions="Click the map, or enter coordinates below, to place the location's point."
        />
        <p
          id="default-location-pending-point"
          class="text-sm text-base-content/70 mt-1"
          aria-live="polite"
        >
          <%= if @pending_point do %>
            Point set to <span class="font-mono">({elem(@pending_point, 0)}, {elem(@pending_point, 1)})</span>.
          <% else %>
            No new point set.
          <% end %>
        </p>

        <.form
          for={@form}
          id="default-location-form"
          phx-change="validate"
          phx-submit="save"
          class="mt-2 flex gap-2 items-end flex-wrap"
        >
          <.input field={@form[:name]} label="Name" required />
          <.input field={@form[:position]} type="number" label="Sort order" />
          <.button
            class="btn btn-primary mb-3"
            disabled={is_nil(@pending_point) and is_nil(@editing.id)}
          >
            Save
          </.button>
          <button type="button" phx-click="cancel" class="btn btn-ghost mb-3">Cancel</button>
        </.form>
      </div>

      <.table id="default-locations" rows={@locations}>
        <:col :let={l} label="Sort">{l.position}</:col>
        <:col :let={l} label="Name">{l.name}</:col>
        <:col :let={l} label="Latitude">{MapHelpers.lat(l.point)}</:col>
        <:col :let={l} label="Longitude">{MapHelpers.lng(l.point)}</:col>
        <:action :let={l}>
          <button
            type="button"
            class="link link-hover"
            phx-click="edit"
            phx-value-id={l.id}
            aria-label={"Edit #{l.name}"}
          >
            Edit
          </button>
        </:action>
        <:action :let={l}>
          <button
            type="button"
            class="link link-hover"
            phx-click="delete"
            phx-value-id={l.id}
            data-confirm="Delete this location?"
            aria-label={"Delete #{l.name}"}
          >
            Delete
          </button>
        </:action>
      </.table>
    </Layouts.app>
    """
  end

  @impl true
  def handle_event("new", _params, socket) do
    {:noreply,
     assign(socket,
       editing: %DefaultLocation{},
       form: to_form(Locations.change_default_location(%DefaultLocation{})),
       pending_point: nil
     )}
  end

  def handle_event("edit", %{"id" => id}, socket) do
    location = Locations.get_default_location!(id)

    {:noreply,
     assign(socket,
       editing: location,
       form: to_form(Locations.change_default_location(location)),
       pending_point: nil
     )}
  end

  def handle_event("cancel", _params, socket),
    do: {:noreply, assign(socket, editing: nil, form: nil, pending_point: nil)}

  def handle_event("point_selected", %{"lat" => lat, "lng" => lng}, socket) do
    {:noreply, assign(socket, pending_point: {lat, lng})}
  end

  # The typed-coordinates alternative to clicking the map.
  def handle_event("set_point", params, socket) do
    case MapHelpers.parse_coordinates(params) do
      {:ok, point} ->
        {:noreply,
         socket
         |> assign(pending_point: {MapHelpers.lat(point), MapHelpers.lng(point)})
         |> MapHelpers.push_point("default-location-map", point)}

      :error ->
        {:noreply, put_flash(socket, :error, MapHelpers.invalid_coordinates_message())}
    end
  end

  def handle_event("validate", %{"default_location" => params}, socket) do
    form =
      socket.assigns.editing
      |> Locations.change_default_location(params)
      |> Map.put(:action, :validate)
      |> to_form()

    {:noreply, assign(socket, form: form)}
  end

  def handle_event("save", %{"default_location" => params}, socket) do
    params =
      case socket.assigns.pending_point do
        {lat, lng} -> Map.put(params, "point", MapHelpers.point(lat, lng))
        nil -> params
      end

    result =
      case socket.assigns.editing do
        %DefaultLocation{id: nil} -> Locations.create_default_location(params)
        location -> Locations.update_default_location(location, params)
      end

    case result do
      {:ok, _} ->
        {:noreply,
         assign(socket,
           editing: nil,
           form: nil,
           pending_point: nil,
           locations: Locations.list_default_locations()
         )}

      {:error, changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  def handle_event("delete", %{"id" => id}, socket) do
    {:ok, _} = Locations.get_default_location!(id) |> Locations.delete_default_location()
    {:noreply, assign(socket, locations: Locations.list_default_locations())}
  end

  defp pending_point({lat, lng}), do: MapHelpers.point(lat, lng)
  defp pending_point(nil), do: nil
end
