defmodule McEmcommWeb.MapHelpers do
  @moduledoc "Shared helpers for building the `data-markers` JSON payload consumed by the LeafletMap hook (§12)."

  @doc "The OSM tile URL template, from `MC_EMCOMM_MAP_TILE_URL`."
  def tile_url, do: Application.get_env(:mc_emcomm, :map_tile_url)

  @doc "Builds a `%Geo.Point{}` from separate lat/lng floats (as pushed by the LeafletPicker hook)."
  def point(lat, lng) when is_number(lat) and is_number(lng) do
    %Geo.Point{coordinates: {lng, lat}, srid: 4326}
  end

  def lat(%Geo.Point{coordinates: {_lng, lat}}), do: lat
  def lat(_), do: nil

  def lng(%Geo.Point{coordinates: {lng, _lat}}), do: lng
  def lng(_), do: nil

  @doc "JSON-encodes a list of `%{point:, title:, radius_m:}` maps into the marker payload the hook expects."
  def markers_json(items) do
    items
    |> Enum.filter(&match?(%Geo.Point{}, &1.point))
    |> Enum.map(fn item ->
      %{
        lat: lat(item.point),
        lng: lng(item.point),
        title: item[:title],
        radius_m: item[:radius_m]
      }
    end)
    |> Jason.encode!()
  end
end
