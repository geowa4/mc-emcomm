defmodule McEmcomm.Aprs.Filter do
  @moduledoc """
  Builds the server-side filter an APRS-IS connection asks for. Filter terms
  are OR'd by the server, so one connection covers every location with a
  radius term (`r/lat/lon/km`) per point plus a budlist term (`b/CALL-SSID`)
  per tracked station so its beacons arrive wherever it drives. The budlist
  names the exact station: an operator's home station under another SSID must
  not reach the net logger. Pure functions: the wire strings are assembled
  here so they can be tested without a socket.
  """

  require Logger

  # aprsc and javAPRSSrvr cap the login/#filter line; warn before we get there.
  @warn_bytes 400

  @doc """
  The filter for `points` (`%Geo.Point{}`, lng/lat) and tracked station ids
  (`K4GWA-9`), or `""` when there are no points, in which case there is no
  net to listen for.
  """
  @spec build([Geo.Point.t()], [String.t()], number()) :: String.t()
  def build([], _stations, _radius_km), do: ""

  def build(points, stations, radius_km) do
    terms = range_terms(points, radius_km) ++ budlist_terms(stations)
    filter = Enum.join(terms, " ")

    if byte_size(filter) > @warn_bytes do
      Logger.warning("APRS-IS filter is #{byte_size(filter)} bytes; servers may truncate it")
    end

    filter
  end

  @doc "The APRS-IS login line, receive-only when `passcode` is \"-1\"."
  @spec login_line(String.t(), String.t(), String.t(), String.t()) :: String.t()
  def login_line(call_sign, passcode, version, filter) do
    "user #{call_sign} pass #{passcode} vers mc_emcomm #{version} filter #{filter}\r\n"
  end

  @doc "The in-band command that replaces the filter on an open connection."
  @spec filter_line(String.t()) :: String.t()
  def filter_line(filter), do: "#filter #{filter}\r\n"

  defp range_terms(points, radius_km) do
    points
    |> Enum.map(fn %Geo.Point{coordinates: {lng, lat}} ->
      {Float.round(lat / 1, 3), Float.round(lng / 1, 3)}
    end)
    |> Enum.uniq()
    |> Enum.sort()
    |> Enum.map(fn {lat, lng} -> "r/#{lat}/#{lng}/#{radius_km}" end)
  end

  defp budlist_terms(stations) do
    stations
    |> Enum.map(&String.upcase/1)
    |> Enum.filter(&Regex.match?(~r/^[A-Z0-9-]+$/, &1))
    |> Enum.uniq()
    |> Enum.sort()
    |> Enum.map(&"b/#{&1}")
  end
end
