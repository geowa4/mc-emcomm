defmodule McEmcomm.Aprs.Packet do
  @moduledoc """
  The only module that reads raw APRS-IS lines (through the `aprs` package).
  It extracts what the net logger needs from a position report and rejects
  everything else, so the parser can be swapped without touching
  `McEmcomm.Net`.
  """

  # Every data type the parser reports for a packet that carries a position:
  # uncompressed and compressed, with or without timestamp/messaging, and both
  # Mic-E encodings. Status, message, object, item, telemetry and weather
  # packets are deliberately not check-ins.
  @position_types [
    :position,
    :position_with_message,
    :timestamped_position,
    :timestamped_position_with_message,
    :mic_e,
    :mic_e_old
  ]

  @typedoc """
  `station` is the full APRS id as transmitted (`K4GWA-4`), `call_sign` its
  base (`K4GWA`, what members are matched on) and `ssid` the suffix, if any.
  """
  @type position :: %{
          station: String.t(),
          call_sign: String.t(),
          ssid: String.t() | nil,
          point: Geo.Point.t(),
          comment: String.t()
        }

  @doc """
  The position a raw APRS-IS line reports, or `:error` for server comments,
  unparseable lines, packets without a position, and positions out of range.
  """
  @spec position_report(String.t()) :: {:ok, position} | :error
  def position_report(line) when is_binary(line) do
    line = String.trim_trailing(line)

    with false <- String.starts_with?(line, "#"),
         {:ok, %{data_type: type, data_extended: %{} = data, base_callsign: base} = packet}
         when type in @position_types and is_binary(base) and base != "" <- parse(line),
         {:ok, point} <- point(data) do
      call_sign = String.upcase(base)
      ssid = ssid(packet[:ssid])

      {:ok,
       %{
         station: station(call_sign, ssid),
         call_sign: call_sign,
         ssid: ssid,
         point: point,
         comment: comment(data[:comment])
       }}
    else
      _ -> :error
    end
  end

  def position_report(_line), do: :error

  # A parser crash on a hostile line is just a line we don't understand.
  defp parse(line) do
    Aprs.parse(line)
  rescue
    _error -> :error
  end

  defp point(%{latitude: lat, longitude: lng}) do
    with {:ok, lat} <- coordinate(lat, 90),
         {:ok, lng} <- coordinate(lng, 180) do
      {:ok, %Geo.Point{coordinates: {lng, lat}, srid: 4326}}
    end
  end

  defp point(_data), do: :error

  defp coordinate(value, limit) do
    case to_float(value) do
      float when is_float(float) and float >= -limit and float <= limit -> {:ok, float}
      _ -> :error
    end
  end

  defp to_float(value) when is_float(value), do: value
  defp to_float(value) when is_integer(value), do: value / 1
  defp to_float(%Decimal{} = value), do: Decimal.to_float(value)
  defp to_float(_value), do: nil

  # The parser reports a missing SSID as nil or "0".
  defp ssid(ssid) when ssid in [nil, "", "0"], do: nil
  defp ssid(ssid) when is_binary(ssid), do: ssid
  defp ssid(ssid) when is_integer(ssid) and ssid > 0, do: Integer.to_string(ssid)
  defp ssid(_ssid), do: nil

  defp station(call_sign, nil), do: call_sign
  defp station(call_sign, ssid), do: "#{call_sign}-#{ssid}"

  defp comment(comment) when is_binary(comment), do: comment
  defp comment(_comment), do: ""
end
