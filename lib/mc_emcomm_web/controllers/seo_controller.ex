defmodule McEmcommWeb.SeoController do
  @moduledoc """
  The crawler files: `robots.txt` and `sitemap.xml`.

  Both are generated rather than served from `priv/static` because they name
  absolute URLs, which come from the endpoint's runtime `:url` config, and
  the sitemap lists whatever operations are currently public.
  """

  use McEmcommWeb, :controller

  alias McEmcomm.Operations

  # Neither file carries a session, nonce, or user data, so a shared cache may
  # keep it for a while; an hour bounds how stale the operations list gets.
  plug :put_public_cache_control

  # Every page a search engine should know about, in nav order.
  @public_paths ~w(/ /about /training /resources /operations /calendar /donations /users/register)

  @doc "The public pages listed in the sitemap, as paths."
  def public_paths, do: @public_paths

  def robots(conn, _params) do
    body = """
    User-agent: *
    Disallow: /a/
    Disallow: /app$
    Disallow: /app/
    Disallow: /admin$
    Disallow: /admin/
    Disallow: /dev/
    Disallow: /users/
    Allow: /users/register
    Sitemap: #{url(~p"/sitemap.xml")}
    """

    text(conn, body)
  end

  def sitemap(conn, _params) do
    static_entries = Enum.map(@public_paths, &sitemap_entry(unverified_url(conn, &1), nil))

    operation_entries =
      [visibility: :public]
      |> Operations.list_operations()
      |> Enum.map(&sitemap_entry(url(~p"/operations/#{&1.id}"), &1.updated_at))

    body = """
    <?xml version="1.0" encoding="UTF-8"?>
    <urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
    #{Enum.join(static_entries ++ operation_entries)}</urlset>
    """

    conn
    |> put_resp_content_type("application/xml")
    |> send_resp(200, body)
  end

  defp sitemap_entry(loc, nil), do: "  <url><loc>#{loc}</loc></url>\n"

  defp sitemap_entry(loc, %DateTime{} = updated_at) do
    "  <url><loc>#{loc}</loc><lastmod>#{DateTime.to_iso8601(updated_at)}</lastmod></url>\n"
  end

  defp put_public_cache_control(conn, _opts) do
    put_resp_header(conn, "cache-control", "public, max-age=3600")
  end
end
