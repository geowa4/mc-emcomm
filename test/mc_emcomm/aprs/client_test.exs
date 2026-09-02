defmodule McEmcomm.Aprs.ClientTest do
  # Shared sandbox mode (async: false) lets the client process query the
  # test's connection without an explicit allowance.
  use McEmcomm.DataCase, async: false

  import ExUnit.CaptureLog

  alias McEmcomm.Aprs.Client
  alias McEmcomm.McEmcommFixtures
  alias McEmcomm.Net
  alias McEmcomm.Net.NetCheckin

  @keyword_packet ~S|W2XYZ-9>APRS,TCPIP*,qAC,T2XYZ:!4309.40N/07736.53W>KEYWORD mobile|

  setup do
    {:ok, listen} =
      :gen_tcp.listen(0, [
        :binary,
        packet: :line,
        active: false,
        reuseaddr: true,
        ip: {127, 0, 0, 1}
      ])

    {:ok, {_ip, port}} = :inet.sockname(listen)
    on_exit(fn -> :gen_tcp.close(listen) end)

    client =
      start_supervised!(
        {Client,
         name: :aprs_client_under_test,
         host: "127.0.0.1",
         port: port,
         call_sign: "WB2EOC",
         passcode: "-1",
         radius_km: 25,
         refresh_ms: :timer.hours(1),
         connect_timeout_ms: 1_000,
         idle_timeout_ms: :timer.minutes(5)}
      )

    %{listen: listen, client: client}
  end

  defp accept(listen) do
    {:ok, socket} = :gen_tcp.accept(listen, 5_000)
    socket
  end

  defp recv(socket) do
    {:ok, line} = :gen_tcp.recv(socket, 0, 5_000)
    line
  end

  defp packet_with_keyword(session) do
    String.replace(@keyword_packet, "KEYWORD", session.aprs_keyword) <> "\r\n"
  end

  test "idles without connecting while no net is active", %{listen: listen, client: client} do
    assert %{status: :idle, filter: ""} = Client.state(client)
    assert {:error, :timeout} = :gen_tcp.accept(listen, 200)
  end

  test "logs in with a filter covering the net locations, checks stations in, and tracks them",
       %{listen: listen, client: client} do
    McEmcommFixtures.default_location_fixture()
    starter = McEmcommFixtures.member_fixture()
    session = McEmcommFixtures.net_session_fixture(starter)
    Net.subscribe(session.id)

    # Starting the net announced a change; the client connects on its own.
    server = accept(listen)

    assert recv(server) ==
             "user WB2EOC pass -1 vers mc_emcomm 0.1.0 filter r/43.157/-77.609/25\r\n"

    assert %{status: :connected} = Client.state(client)

    :ok = :gen_tcp.send(server, "# logresp WB2EOC unverified, server T2TEST\r\n")
    :ok = :gen_tcp.send(server, "garbage that is not a packet\r\n")
    :ok = :gen_tcp.send(server, "W2XYZ>APRS,TCPIP*:>status only #{session.aprs_keyword}\r\n")
    :ok = :gen_tcp.send(server, packet_with_keyword(session))

    assert_receive {:checkin_added, %NetCheckin{call_sign: "W2XYZ", aprs_call_sign: "W2XYZ-9"}},
                   5_000

    # The new station is now tracked, so the filter gains its budlist term.
    assert recv(server) == "#filter r/43.157/-77.609/25 b/W2XYZ-9\r\n"

    # Ending the net empties the filter and the client hangs up.
    {:ok, _ended} = Net.end_session(session)
    assert {:error, :closed} = :gen_tcp.recv(server, 0, 5_000)
    assert %{status: :idle, filter: ""} = Client.state(client)
  end

  test "reconnects with the current filter after the server drops it",
       %{listen: listen, client: client} do
    McEmcommFixtures.default_location_fixture()
    starter = McEmcommFixtures.member_fixture()
    _session = McEmcommFixtures.net_session_fixture(starter)

    first = accept(listen)
    assert recv(first) =~ "user WB2EOC"

    log =
      capture_log(fn ->
        :ok = :gen_tcp.close(first)
        second = accept(listen)
        assert recv(second) =~ "filter r/43.157/-77.609/25"
        assert %{status: :connected} = Client.state(client)
      end)

    assert log =~ "reconnecting"
  end
end
