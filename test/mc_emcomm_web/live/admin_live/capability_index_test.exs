defmodule McEmcommWeb.AdminLive.CapabilityIndexTest do
  use McEmcommWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias McEmcomm.Capabilities
  alias McEmcomm.McEmcommFixtures

  setup %{conn: conn} do
    scope = McEmcommFixtures.admin_scope_fixture()
    %{conn: log_in_user(conn, scope.user)}
  end

  test "creating, editing, and deleting a capability", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/admin/capabilities")

    lv |> element("button", "New capability") |> render_click()
    html = lv |> form("#capability-form", capability: %{name: "APRS"}) |> render_submit()
    assert html =~ "APRS"

    capability = Enum.find(Capabilities.list_capabilities(), &(&1.name == "APRS"))

    lv |> element("a", "Edit") |> render_click()
    lv |> form("#capability-form", capability: %{name: "APRS Digipeater"}) |> render_submit()
    assert Capabilities.get_capability!(capability.id).name == "APRS Digipeater"

    lv |> element("a", "Delete") |> render_click()
    assert Capabilities.list_capabilities() == []
  end

  test "cancel clears the form without saving", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/admin/capabilities")

    lv |> element("button", "New capability") |> render_click()
    assert has_element?(lv, "#capability-form")

    lv |> element("button", "Cancel") |> render_click()
    refute has_element?(lv, "#capability-form")
  end
end
