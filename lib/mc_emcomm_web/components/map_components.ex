defmodule McEmcommWeb.MapComponents do
  @moduledoc """
  Leaflet map components (spec §12).

  Both maps are drawn by JavaScript hooks, so each carries an accessible name
  and, for the picker, a coordinate form that does the same job as clicking:
  a screen-reader or keyboard user can place the point without a pointer.
  """
  use Phoenix.Component

  import McEmcommWeb.CoreComponents

  alias McEmcommWeb.MapHelpers

  @doc """
  A read-only map of markers, named for assistive technology. The page is
  expected to list the same places in text nearby.
  """
  attr :id, :string, required: true
  attr :label, :string, required: true, doc: "the accessible name of the map"
  attr :markers_json, :string, required: true
  attr :tile_url, :string, default: nil
  attr :rest, :global

  def static_map(assigns) do
    ~H"""
    <div
      id={@id}
      phx-hook="LeafletMap"
      phx-update="ignore"
      class="map-canvas"
      role="region"
      aria-label={@label}
      data-markers={@markers_json}
      data-tile-url={@tile_url}
      {@rest}
    >
    </div>
    """
  end

  @doc """
  A map for choosing one point, plus a latitude/longitude form.

  Clicking the map pushes `point_selected` with float `lat`/`lng`; submitting
  the form pushes `@on_submit` (default `"set_point"`) with string `lat`/`lng`,
  which `McEmcommWeb.MapHelpers.parse_coordinates/1` turns into floats. After
  handling either, the LiveView calls `McEmcommWeb.MapHelpers.push_point/4` so
  the pin on the map follows.
  """
  attr :id, :string, required: true
  attr :label, :string, required: true, doc: "the accessible name of the map"
  attr :point, :any, default: nil, doc: "the current `%Geo.Point{}` or nil"
  attr :tile_url, :string, default: nil
  attr :on_submit, :string, default: "set_point"

  attr :instructions, :string,
    default: "Click the map to drop a pin, or enter the coordinates below."

  def map_picker(assigns) do
    ~H"""
    <p id={"#{@id}-instructions"} class="text-sm text-base-content/70 mb-1">{@instructions}</p>
    <div
      id={@id}
      phx-hook="LeafletPicker"
      phx-update="ignore"
      class="map-canvas"
      role="application"
      aria-label={@label}
      aria-describedby={"#{@id}-instructions"}
      data-lat={MapHelpers.lat(@point)}
      data-lng={MapHelpers.lng(@point)}
      data-tile-url={@tile_url}
    >
    </div>
    <form
      id={"#{@id}-coordinates"}
      phx-submit={@on_submit}
      class="mt-2 flex flex-wrap gap-2 items-end"
      aria-label={"#{@label}: coordinates"}
    >
      <.input
        type="number"
        id={"#{@id}-lat"}
        name="lat"
        label="Latitude"
        value={MapHelpers.lat(@point)}
        step="any"
        min="-90"
        max="90"
        required
      />
      <.input
        type="number"
        id={"#{@id}-lng"}
        name="lng"
        label="Longitude"
        value={MapHelpers.lng(@point)}
        step="any"
        min="-180"
        max="180"
        required
      />
      <button type="submit" class="btn btn-secondary btn-sm mb-3">Set point</button>
    </form>
    """
  end
end
