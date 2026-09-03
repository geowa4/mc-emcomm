defmodule McEmcommWeb.SeoMetadataTest do
  @moduledoc """
  The root layout's search and link-preview metadata: description, canonical
  URL, Open Graph and Twitter tags, the Organization JSON-LD block, and the
  `noindex` opt-out that keeps crawlers off the pages that must not be
  indexed.
  """

  use McEmcommWeb.ConnCase, async: true

  alias McEmcomm.McEmcommFixtures

  defp document(conn, path) do
    conn |> get(path) |> html_response(200) |> LazyHTML.from_document()
  end

  defp content(document, selector) do
    document |> LazyHTML.query(selector) |> LazyHTML.attribute("content")
  end

  test "a public page carries its own description on every preview tag", %{conn: conn} do
    document = document(conn, ~p"/about")

    assert [description] = content(document, "meta[name='description']")
    assert description =~ "Monroe County ARES/RACES"
    refute description == McEmcommWeb.Layouts.default_description()
    assert content(document, "meta[property='og:description']") == [description]
    assert content(document, "meta[name='twitter:description']") == [description]
  end

  test "the home page sets its title and description through the controller", %{conn: conn} do
    document = document(conn, ~p"/")

    assert content(document, "meta[property='og:title']") == [
             "Home · Monroe County ARES/RACES"
           ]

    assert [description] = content(document, "meta[name='description']")
    refute description == McEmcommWeb.Layouts.default_description()
  end

  test "an indexable page links its canonical URL and is not marked noindex", %{conn: conn} do
    document = document(conn, ~p"/training")

    assert document |> LazyHTML.query("link[rel='canonical']") |> LazyHTML.attribute("href") ==
             [url(~p"/training")]

    assert content(document, "meta[property='og:url']") == [url(~p"/training")]
    assert content(document, "meta[name='robots']") == []
  end

  test "link previews get a raster image and the organization's handle", %{conn: conn} do
    document = document(conn, ~p"/")

    assert [image] = content(document, "meta[property='og:image']")
    assert String.ends_with?(image, ".png")
    assert content(document, "meta[name='twitter:image']") == [image]
    assert content(document, "meta[name='twitter:card']") == ["summary"]
    assert content(document, "meta[name='twitter:site']") == ["@MCARESNY"]
  end

  test "every page embeds Organization structured data", %{conn: conn} do
    document = document(conn, ~p"/donations")

    json =
      document
      |> LazyHTML.query("script[type='application/ld+json']")
      |> LazyHTML.text()
      |> String.trim()

    assert %{
             "@type" => "Organization",
             "name" => "Monroe County ARES/RACES",
             "address" => %{"addressLocality" => "Rochester"},
             "sameAs" => same_as
           } = JSON.decode!(json)

    assert "https://www.facebook.com/MCARESNY" in same_as
  end

  test "a public operation describes itself from its own description", %{conn: conn} do
    operation =
      McEmcommFixtures.operation_fixture(%{
        "visibility" => "public",
        "title" => "Turkey Trot",
        "description" => "Communications for the Thanksgiving 5K."
      })

    document = document(conn, ~p"/operations/#{operation.id}")

    assert content(document, "meta[name='description']") == [
             "Communications for the Thanksgiving 5K."
           ]

    assert content(document, "meta[property='og:title']") == [
             "Turkey Trot · Monroe County ARES/RACES"
           ]
  end

  test "the login page has a title and is kept out of the index", %{conn: conn} do
    document = document(conn, ~p"/users/log-in")

    assert content(document, "meta[property='og:title']") == [
             "Log in · Monroe County ARES/RACES"
           ]

    assert content(document, "meta[name='robots']") == ["noindex, nofollow"]
    assert LazyHTML.query(document, "link[rel='canonical']") |> Enum.empty?()
  end

  test "the registration page is indexable with its own description", %{conn: conn} do
    document = document(conn, ~p"/users/register")

    assert content(document, "meta[property='og:title']") == [
             "Register · Monroe County ARES/RACES"
           ]

    assert [description] = content(document, "meta[name='description']")
    assert description =~ "membership"
    assert content(document, "meta[name='robots']") == []
  end

  test "the sighting page is kept out of the index by header and tag", %{conn: conn} do
    asset = McEmcommFixtures.asset_fixture()

    conn = get(conn, ~p"/a/#{asset.public_id}/s")

    assert get_resp_header(conn, "x-robots-tag") == ["noindex, nofollow"]

    document = conn |> html_response(200) |> LazyHTML.from_document()
    assert content(document, "meta[name='robots']") == ["noindex, nofollow"]
    assert LazyHTML.query(document, "link[rel='canonical']") |> Enum.empty?()
  end
end
