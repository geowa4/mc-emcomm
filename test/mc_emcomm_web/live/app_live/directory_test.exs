defmodule McEmcommWeb.AppLive.DirectoryTest do
  use McEmcommWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias McEmcomm.AccountsFixtures
  alias McEmcomm.McEmcommFixtures
  alias McEmcomm.Members

  @point %Geo.Point{coordinates: {-77.6088, 43.1566}, srid: 4326}

  defp member(name, call_sign, profile \\ %{}) do
    member = McEmcommFixtures.member_fixture(%{name: name, call_sign: call_sign})
    {:ok, updated} = Members.update_profile(member, profile)
    %{updated | user: member.user}
  end

  defp markers(lv) do
    lv
    |> element("#directory-map")
    |> render()
    |> LazyHTML.from_fragment()
    |> LazyHTML.attribute("data-markers")
    |> List.first()
    |> Jason.decode!()
  end

  setup %{conn: conn} do
    viewer = member("Avery Adams", "K2AAA", %{qth_point: @point, license_class: :general})
    %{conn: log_in_user(conn, viewer.user), viewer: viewer}
  end

  describe "access" do
    test "redirects an anonymous visitor to log in" do
      assert {:error, {:redirect, %{to: "/users/log-in"}}} =
               live(build_conn(), ~p"/app/directory")
    end

    test "redirects a user with no member profile" do
      conn = log_in_user(build_conn(), AccountsFixtures.user_fixture())

      assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/app/directory")
    end

    test "redirects a pending member" do
      pending = McEmcommFixtures.pending_member_fixture()
      conn = log_in_user(build_conn(), pending.user)

      assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/app/directory")
    end

    test "is linked from the member dashboard", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/app")

      assert has_element?(lv, "#dashboard-directory[href='/app/directory']")
    end
  end

  describe "list" do
    test "shows approved members and leaves out everyone else", %{conn: conn, viewer: viewer} do
      other = member("Blake Brown", "W2BBB")
      pending = McEmcommFixtures.pending_member_fixture(%{name: "Parker Pending"})

      {:ok, lv, _html} = live(conn, ~p"/app/directory")

      assert has_element?(lv, "#directory-member-#{viewer.id}", "Avery Adams")
      assert has_element?(lv, "#directory-member-#{viewer.id}", "K2AAA")
      assert has_element?(lv, "#directory-member-#{viewer.id}", "General")

      assert has_element?(
               lv,
               "#directory-member-#{other.id} a[href='mailto:#{other.user.email}']",
               other.user.email
             )

      assert has_element?(lv, "#directory-member-#{viewer.id}", "43.1566, -77.6088")
      assert has_element?(lv, "#directory-member-#{other.id}", "Not set")
      refute has_element?(lv, "#directory-member-#{pending.id}")
      assert has_element?(lv, "#directory-count", "Showing 1 to 2 of 2 members.")
    end

    test "shows the positions a member holds", %{conn: conn, viewer: viewer} do
      position = McEmcommFixtures.position_fixture(%{name: "Directory Steward"})
      {:ok, _member} = Members.assign_position(viewer, position)

      {:ok, lv, _html} = live(conn, ~p"/app/directory")

      assert has_element?(lv, "#directory-member-#{viewer.id}", "Directory Steward")
    end

    test "never shows an address or an emergency contact", %{conn: conn} do
      other =
        member("Blake Brown", "W2BBB", %{
          qth_address: "1 Hidden Lane",
          emergency_contact_name: "Casey Contact",
          emergency_contact_phone: "585-555-0100"
        })

      {:ok, lv, _html} = live(conn, ~p"/app/directory")

      assert has_element?(lv, "#directory-member-#{other.id}")
      refute has_element?(lv, "#main-content", "1 Hidden Lane")
      refute has_element?(lv, "#main-content", "Casey Contact")
      refute has_element?(lv, "#main-content", "585-555-0100")
    end
  end

  describe "search" do
    test "narrows the list by name or call sign and keeps the search in the URL",
         %{conn: conn, viewer: viewer} do
      other = member("Blake Brown", "W2BBB")

      {:ok, lv, _html} = live(conn, ~p"/app/directory")

      lv |> form("#directory-search-form", %{"q" => "w2b"}) |> render_change()

      assert_patch(lv, ~p"/app/directory?q=w2b")
      assert has_element?(lv, "#directory-member-#{other.id}")
      refute has_element?(lv, "#directory-member-#{viewer.id}")

      lv |> form("#directory-search-form", %{"q" => "avery"}) |> render_submit()

      assert_patch(lv, ~p"/app/directory?q=avery")
      assert has_element?(lv, "#directory-member-#{viewer.id}")
      refute has_element?(lv, "#directory-member-#{other.id}")
    end

    test "finds a member by email", %{conn: conn, viewer: viewer} do
      other = member("Blake Brown", "W2BBB")

      {:ok, lv, _html} = live(conn, ~p"/app/directory?#{[q: other.user.email]}")

      assert has_element?(lv, "#directory-member-#{other.id}")
      refute has_element?(lv, "#directory-member-#{viewer.id}")
    end

    test "says so when nobody matches and offers a way back", %{conn: conn, viewer: viewer} do
      {:ok, lv, _html} = live(conn, ~p"/app/directory?q=nobody")

      assert has_element?(lv, "#directory-empty")
      refute has_element?(lv, "#directory-members")

      lv |> element("#directory-clear-search") |> render_click()

      assert_patch(lv, ~p"/app/directory")
      assert has_element?(lv, "#directory-member-#{viewer.id}")
    end
  end

  describe "sorting" do
    test "orders the list as chosen", %{conn: conn, viewer: viewer} do
      other = member("Blake Brown", "A2BBB")

      {:ok, lv, _html} = live(conn, ~p"/app/directory")

      assert has_element?(lv, "#directory-members tr:first-child#directory-member-#{viewer.id}")

      lv |> form("#directory-search-form", %{"order" => "call-sign"}) |> render_change()

      assert_patch(lv, ~p"/app/directory?order=call-sign")
      assert has_element?(lv, "#directory-members tr:first-child#directory-member-#{other.id}")
      assert has_element?(lv, "#directory-order option[value='call-sign'][selected]")
    end

    test "falls back to name order for an order it does not know",
         %{conn: conn, viewer: viewer} do
      member("Blake Brown", "A2BBB")

      {:ok, lv, _html} = live(conn, ~p"/app/directory?order=emergency_contact_phone")

      assert has_element?(lv, "#directory-members tr:first-child#directory-member-#{viewer.id}")
      assert has_element?(lv, "#directory-order option[value='name'][selected]")
    end
  end

  describe "pagination" do
    setup do
      # With the viewer, "Avery Adams", that makes 27 members: two pages.
      members = for n <- 10..35, do: member("Member #{n}", "W2A#{n}")
      %{first: List.first(members), last: List.last(members)}
    end

    test "pages through the list", %{conn: conn, viewer: viewer, last: last} do
      {:ok, lv, _html} = live(conn, ~p"/app/directory")

      assert has_element?(lv, "#directory-count", "Showing 1 to 25 of 27 members.")
      assert has_element?(lv, "#directory-page", "Page 1 of 2")
      assert has_element?(lv, "#directory-member-#{viewer.id}")
      refute has_element?(lv, "#directory-member-#{last.id}")
      refute has_element?(lv, "#directory-previous-page")

      lv |> element("#directory-next-page") |> render_click()

      assert_patch(lv, ~p"/app/directory?page=2")
      assert has_element?(lv, "#directory-count", "Showing 26 to 27 of 27 members.")
      assert has_element?(lv, "#directory-member-#{last.id}")
      refute has_element?(lv, "#directory-member-#{viewer.id}")
      refute has_element?(lv, "#directory-next-page")

      lv |> element("#directory-previous-page") |> render_click()

      assert_patch(lv, ~p"/app/directory")
      assert has_element?(lv, "#directory-member-#{viewer.id}")
    end

    test "keeps the search and order on the page links", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/app/directory?q=member&order=call-sign-desc")

      lv |> element("#directory-next-page") |> render_click()

      assert_patch(lv, ~p"/app/directory?order=call-sign-desc&page=2&q=member")
    end

    test "a new search starts again from the first page", %{conn: conn, first: first} do
      {:ok, lv, _html} = live(conn, ~p"/app/directory?page=2")

      lv |> form("#directory-search-form", %{"q" => "member 10"}) |> render_change()

      assert_patch(lv, ~p"/app/directory?q=member+10")
      assert has_element?(lv, "#directory-member-#{first.id}")
    end

    test "shows the last page for a page past the end", %{conn: conn, last: last} do
      {:ok, lv, _html} = live(conn, ~p"/app/directory?page=99")

      assert has_element?(lv, "#directory-page", "Page 2 of 2")
      assert has_element?(lv, "#directory-member-#{last.id}")
    end

    test "shows the first page for a page that is not a number", %{conn: conn, viewer: viewer} do
      {:ok, lv, _html} = live(conn, ~p"/app/directory?page=two")

      assert has_element?(lv, "#directory-page", "Page 1 of 2")
      assert has_element?(lv, "#directory-member-#{viewer.id}")
    end
  end

  describe "map" do
    test "marks every approved member with a home location, on any page", %{conn: conn} do
      for n <- 10..35, do: member("Member #{n}", "W2A#{n}", %{qth_point: @point})
      member("No Location", "W2NNN")

      pending = McEmcommFixtures.pending_member_fixture(%{name: "Parker Pending"})
      {:ok, _member} = Members.update_profile(pending, %{qth_point: @point})

      {:ok, lv, _html} = live(conn, ~p"/app/directory?page=2")

      titles = lv |> markers() |> Enum.map(& &1["title"])

      assert length(titles) == 27
      assert "K2AAA — Avery Adams" in titles
      assert "W2A35 — Member 35" in titles
      refute Enum.any?(titles, &(&1 =~ "Parker Pending"))
      refute Enum.any?(titles, &(&1 =~ "No Location"))

      assert has_element?(
               lv,
               "#directory-map-summary",
               "27 of 28 members have set a home location."
             )
    end

    test "follows the search", %{conn: conn} do
      member("Blake Brown", "W2BBB", %{qth_point: @point})

      {:ok, lv, _html} = live(conn, ~p"/app/directory?q=blake")

      assert [%{"title" => "W2BBB — Blake Brown", "lat" => 43.1566, "lng" => -77.6088}] =
               markers(lv)
    end

    test "has an accessible name", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/app/directory")

      assert has_element?(lv, "#directory-map[role='region'][aria-label]")
    end
  end
end
