defmodule McEmcommWeb.Plugs.RecordSighting do
  @moduledoc """
  Update point 0 of the sighting-first QR flow (spec §9): runs before the
  LiveView plug so a `sightings` row is created from request metadata even
  if the WebSocket never connects. The sighting id and its session token are
  stashed in the plug session so the LiveView's disconnected AND connected
  mounts (which both receive that session) can find the same row for update
  points 1 and 2.
  """

  import Plug.Conn

  alias McEmcomm.Assets
  alias McEmcomm.Sightings

  def init(opts), do: opts

  def call(%Plug.Conn{path_params: %{"public_id" => public_id}} = conn, _opts) do
    case Assets.get_asset_by_public_id(public_id) do
      # No row is written for an unknown or retired asset, and any sighting
      # left in the session by an earlier scan is dropped so the LiveView
      # cannot fall back to it for a different asset.
      nil ->
        forget_sighting(conn)

      %{active: false} ->
        forget_sighting(conn)

      asset ->
        session_token = Base.url_encode64(:crypto.strong_rand_bytes(24))

        {:ok, sighting} =
          Sightings.record_visit(%{
            asset_id: asset.id,
            session_token: session_token,
            visited_at: DateTime.utc_now(),
            remote_ip: remote_ip(conn),
            fly_region: get_req_header_value(conn, "fly-region"),
            user_agent: get_req_header_value(conn, "user-agent"),
            sec_ch_ua: get_req_header_value(conn, "sec-ch-ua"),
            sec_ch_ua_platform: get_req_header_value(conn, "sec-ch-ua-platform"),
            sec_ch_ua_mobile: get_req_header_value(conn, "sec-ch-ua-mobile"),
            accept_language: get_req_header_value(conn, "accept-language"),
            referer: get_req_header_value(conn, "referer")
          })

        conn
        |> put_session(:sighting_id, sighting.id)
        |> put_session(:sighting_session_token, session_token)
    end
  end

  def call(conn, _opts), do: conn

  defp forget_sighting(conn) do
    conn
    |> delete_session(:sighting_id)
    |> delete_session(:sighting_session_token)
  end

  defp remote_ip(conn) do
    case get_req_header_value(conn, "fly-client-ip") || first_forwarded_for(conn) do
      nil ->
        conn.remote_ip |> :inet.ntoa() |> to_string()

      ip ->
        ip
    end
  end

  defp first_forwarded_for(conn) do
    case get_req_header_value(conn, "x-forwarded-for") do
      nil -> nil
      value -> value |> String.split(",") |> List.first() |> String.trim()
    end
  end

  defp get_req_header_value(conn, header) do
    case get_req_header(conn, header) do
      [value | _] -> value
      [] -> nil
    end
  end
end
