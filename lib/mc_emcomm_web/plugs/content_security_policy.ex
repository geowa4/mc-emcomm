defmodule McEmcommWeb.Plugs.ContentSecurityPolicy do
  @moduledoc """
  Sends the Content-Security-Policy header and assigns the per-request nonce
  that the inline scripts on our pages carry (`@csp_nonce` in the root layout,
  and LiveDashboard via its `:csp_nonce_assign_key` router option).

  `script-src` is nonce-only — no `'unsafe-inline'` — which is the half that
  matters: injected markup carries no nonce and never executes. `style-src`
  keeps `'unsafe-inline'` because Leaflet and LiveDashboard both write style
  attributes as they render; CSS injection is a much weaker vector, and
  locking it down would break the maps.

  Two of the origins are not `'self'` and come from runtime configuration, so
  the policy is assembled per request rather than baked in at compile time:

    * the OSM tile endpoint (`MC_EMCOMM_MAP_TILE_URL`), which Leaflet loads as
      images (§12);
    * the Tigris bucket (`AWS_ENDPOINT_URL_S3`), which serves presigned image
      URLs (`img-src`) and receives `external:` uploads posted straight from
      the browser by XHR (`connect-src`, §11).

  Either is left out when unset, which is what dev and test do — they stub the
  presign functions rather than talking to a bucket.
  """
  @behaviour Plug

  import Plug.Conn

  # The Calendar page embeds a Google Calendar; `'self'` covers the
  # LiveReloader iframe in dev.
  @frame_sources ["'self'", "https://calendar.google.com"]

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    nonce = 16 |> :crypto.strong_rand_bytes() |> Base.encode64()

    conn
    |> assign(:csp_nonce, nonce)
    |> put_resp_header("content-security-policy", policy(nonce))
  end

  defp policy(nonce) do
    tiles = origin(Application.get_env(:mc_emcomm, :map_tile_url))
    storage = origin(Application.get_env(:mc_emcomm, :storage_url))

    Enum.join(
      [
        "default-src 'self'",
        "base-uri 'self'",
        "object-src 'none'",
        "frame-ancestors 'self'",
        "form-action 'self'",
        "script-src 'self' 'nonce-#{nonce}'",
        "style-src 'self' 'unsafe-inline'",
        "font-src 'self' data:",
        directive("img-src", ["'self'", "data:", tiles, storage]),
        directive("connect-src", ["'self'", storage]),
        directive("frame-src", @frame_sources)
      ],
      "; "
    )
  end

  defp directive(name, sources) do
    sources = sources |> Enum.reject(&is_nil/1) |> Enum.uniq() |> Enum.join(" ")
    name <> " " <> sources
  end

  # A CSP source only needs the scheme, host, and non-default port.
  defp origin(url) when is_binary(url) and url != "" do
    case URI.parse(url) do
      %URI{scheme: scheme, host: host, port: port} when is_binary(scheme) and is_binary(host) ->
        URI.to_string(%URI{scheme: scheme, host: host, port: port})

      _not_absolute ->
        nil
    end
  end

  defp origin(_url), do: nil
end
