defmodule McEmcommWeb.SeoControllerTest do
  use McEmcommWeb.ConnCase, async: true

  alias McEmcomm.McEmcommFixtures

  describe "GET /robots.txt" do
    test "keeps crawlers off the sighting, portal, and account routes", %{conn: conn} do
      body = conn |> get(~p"/robots.txt") |> text_response(200)
      lines = String.split(body, "\n", trim: true)

      assert "User-agent: *" in lines
      assert "Disallow: /a/" in lines
      assert "Disallow: /app/" in lines
      assert "Disallow: /admin/" in lines
      assert "Disallow: /users/" in lines
      assert "Allow: /users/register" in lines
    end

    test "points at the sitemap on the configured public origin", %{conn: conn} do
      body = conn |> get(~p"/robots.txt") |> text_response(200)

      assert body =~ "Sitemap: #{url(~p"/sitemap.xml")}"
    end
  end

  describe "GET /sitemap.xml" do
    test "lists every public page and each public operation", %{conn: conn} do
      public = McEmcommFixtures.operation_fixture(%{"visibility" => "public"})
      members_only = McEmcommFixtures.operation_fixture(%{"visibility" => "members"})

      conn = get(conn, ~p"/sitemap.xml")
      body = response(conn, 200)

      assert response_content_type(conn, :xml)

      locs =
        body
        |> LazyHTML.from_fragment()
        |> LazyHTML.query("url > loc")
        |> LazyHTML.text(separator: "\n")
        |> String.split("\n", trim: true)

      for path <- McEmcommWeb.SeoController.public_paths() do
        assert unverified_url(conn, path) in locs
      end

      assert url(~p"/operations/#{public.id}") in locs
      refute url(~p"/operations/#{members_only.id}") in locs
    end
  end
end
