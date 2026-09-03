defmodule McEmcommWeb.MapHelpers do
  @moduledoc "Shared helpers for building the `data-markers` JSON payload consumed by the LeafletMap hook (§12)."

  @doc "The OSM tile URL template, from `MC_EMCOMM_MAP_TILE_URL`."
  def tile_url, do: Application.get_env(:mc_emcomm, :map_tile_url)

  @doc "Builds a `%Geo.Point{}` from separate lat/lng floats (as pushed by the LeafletPicker hook)."
  def point(lat, lng) when is_number(lat) and is_number(lng) do
    %Geo.Point{coordinates: {lng, lat}, srid: 4326}
  end

  @doc """
  Parses the `lat`/`lng` strings a coordinate form submits (see
  `McEmcommWeb.MapComponents.map_picker/1`) into a `%Geo.Point{}`, or
  `:error` when either is missing, malformed, or out of range.
  """
  @spec parse_coordinates(map()) :: {:ok, Geo.Point.t()} | :error
  def parse_coordinates(%{"lat" => lat, "lng" => lng}) do
    with {:ok, lat} <- parse_float(lat, -90.0, 90.0),
         {:ok, lng} <- parse_float(lng, -180.0, 180.0) do
      {:ok, point(lat, lng)}
    end
  end

  def parse_coordinates(_params), do: :error

  defp parse_float(value, min, max) when is_binary(value) do
    case Float.parse(String.trim(value)) do
      {float, ""} when float >= min and float <= max -> {:ok, float}
      _invalid -> :error
    end
  end

  defp parse_float(_value, _min, _max), do: :error

  @doc "Moves the pin on the `LeafletPicker` map with the given DOM id to `point`."
  def push_point(socket, map_id, %Geo.Point{} = point) do
    Phoenix.LiveView.push_event(socket, "picker:set_point", %{
      id: map_id,
      lat: lat(point),
      lng: lng(point)
    })
  end

  @doc "The message shown when a coordinate form is submitted with unusable values."
  def invalid_coordinates_message,
    do: "Enter a latitude from -90 to 90 and a longitude from -180 to 180."

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
