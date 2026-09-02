defmodule McEmcomm.Aprs.PacketTest do
  use ExUnit.Case, async: true

  alias McEmcomm.Aprs.Packet

  describe "position_report/1" do
    test "an uncompressed position keeps the station, its base call sign and the comment" do
      line = ~S|K4GWA-4>APRS,TCPIP*,qAC,T2XYZ:!4309.40N/07736.53W>MCNET test| <> "\r\n"

      assert {:ok, position} = Packet.position_report(line)
      assert position.station == "K4GWA-4"
      assert position.call_sign == "K4GWA"
      assert position.ssid == "4"
      assert position.comment == "MCNET test"
      assert %Geo.Point{coordinates: {lng, lat}, srid: 4326} = position.point
      assert_in_delta lat, 43.1567, 0.001
      assert_in_delta lng, -77.6088, 0.001
    end

    test "a timestamped position with messaging is a position too" do
      line = ~S|K4GWA-4>APRS,TCPIP*,qAC,T2XYZ:@092345z4309.40N/07736.53W>MCNET test|

      assert {:ok, position} = Packet.position_report(line)
      assert position.comment == "MCNET test"
      assert %Geo.Point{coordinates: {lng, lat}} = position.point
      assert_in_delta lat, 43.1567, 0.001
      assert_in_delta lng, -77.6088, 0.001
    end

    test "a compressed position is decoded" do
      line = ~S|K4GWA>APRS,TCPIP*,qAC,T2XYZ:=/5L!!<*e7>7P[MCNET compressed|

      assert {:ok, position} = Packet.position_report(line)
      assert position.comment == "MCNET compressed"
      assert %Geo.Point{coordinates: {lng, lat}} = position.point
      assert_in_delta lat, 49.5, 0.001
      assert_in_delta lng, -72.75, 0.001
    end

    test "a Mic-E position (the format mobile radios send) is decoded" do
      line = ~S|K4GWA-9>S32UVT,WIDE1-1,qAR,W2XYZ:`(_fn"Oj/]"4T}MCNET mobile|

      assert {:ok, position} = Packet.position_report(line)
      assert position.station == "K4GWA-9"
      assert position.call_sign == "K4GWA"
      assert position.comment =~ "MCNET mobile"
      assert %Geo.Point{coordinates: {lng, lat}} = position.point
      assert_in_delta lat, 33.4273, 0.001
      assert_in_delta lng, -112.129, 0.001
    end

    test "a station without an SSID has none" do
      line = ~S|k4gwa>APRS,TCPIP*,qAC,T2XYZ:!4309.40N/07736.53W>hello|

      assert {:ok, position} = Packet.position_report(line)
      assert position.station == "K4GWA"
      assert position.call_sign == "K4GWA"
      assert is_nil(position.ssid)
    end

    test "a position without a comment has an empty one" do
      assert {:ok, %{comment: ""}} =
               Packet.position_report(~S|K4GWA>APRS,TCPIP*:!4309.40N/07736.53W>|)
    end

    test "status and message packets are not positions" do
      assert :error = Packet.position_report(~S|K4GWA>APRS,TCPIP*:>status MCNET|)
      assert :error = Packet.position_report(~S|K4GWA>APRS,TCPIP*::W2XYZ    :message MCNET{1|)
    end

    test "server comments, garbage and non-strings are rejected" do
      assert :error = Packet.position_report("# aprsc 2.1.15 1 Sep 2026 12:00:00 GMT T2XYZ\r\n")
      assert :error = Packet.position_report("# logresp WB2EOC unverified, server T2XYZ")
      assert :error = Packet.position_report("garbage")
      assert :error = Packet.position_report("")
      assert :error = Packet.position_report(nil)
      assert :error = Packet.position_report(~S|K4GWA>APRS,TCPIP*:!not a position at all|)
    end
  end
end
