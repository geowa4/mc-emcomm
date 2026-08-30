defmodule MyAppWeb.InboxLiveTest do
  use MyAppWeb.ConnCase, async: true

  import Mox
  import Phoenix.LiveViewTest
  import MyApp.ResendHelpers

  alias MyApp.Inbound
  alias MyApp.ResendMock

  setup :verify_on_exit!
  setup :register_and_log_in_user

  test "redirects anonymous visitors to log in" do
    conn = build_conn()
    assert {:error, {:redirect, %{to: "/users/log-in"}}} = live(conn, ~p"/inbox")
  end

  test "backfills only the current user's emails from the Receiving API", %{
    conn: conn,
    user: user
  } do
    mine =
      received_email(%{id: "em_mine", from: "Me <#{String.upcase(user.email)}>", subject: "Mine"})

    other =
      received_email(%{id: "em_other", from: "someone-else@example.com", subject: "Not mine"})

    expect(ResendMock, :list_received_all, fn -> {:ok, [other, mine]} end)

    {:ok, view, _html} = live(conn, ~p"/inbox")

    assert has_element?(view, "#inbox-address", user.email)

    render_async(view)

    refute has_element?(view, "#inbox-loading")
    assert has_element?(view, "#emails-em_mine", "Mine")
    refute has_element?(view, "#emails-em_other")
  end

  test "shows a flash when the backfill fails", %{conn: conn} do
    expect(ResendMock, :list_received_all, fn -> {:error, :econnrefused} end)

    {:ok, view, _html} = live(conn, ~p"/inbox")
    render_async(view)

    assert has_element?(view, "#flash-error", "Could not load inbox history")
    refute has_element?(view, "#inbox-loading")
  end

  test "new emails from the webhook appear live without a remount", %{conn: conn, user: user} do
    expect(ResendMock, :list_received_all, fn -> {:ok, []} end)

    {:ok, view, _html} = live(conn, ~p"/inbox")
    render_async(view)

    event =
      received_event(%{email_id: "em_live", from: "Me <#{user.email}>", subject: "Live update"})

    :ok = Inbound.handle_event(event)

    assert has_element?(view, "#emails-em_live", "Live update")
  end

  test "emails from other senders are not delivered", %{conn: conn} do
    expect(ResendMock, :list_received_all, fn -> {:ok, []} end)

    {:ok, view, _html} = live(conn, ~p"/inbox")
    render_async(view)

    :ok = Inbound.handle_event(received_event(%{email_id: "em_spoof", from: "other@example.com"}))

    refute has_element?(view, "#emails-em_spoof")
  end

  test "is reachable through PhoenixTest", %{conn: conn, user: user} do
    expect(ResendMock, :list_received_all, fn -> {:ok, []} end)

    conn
    |> visit(~p"/inbox")
    |> assert_has("#inbox-address", text: user.email)
  end
end
