defmodule McEmcomm.Aprs.FilterTest do
  use ExUnit.Case, async: true

  alias McEmcomm.Aprs.Filter

  defp point(lng, lat), do: %Geo.Point{coordinates: {lng, lat}, srid: 4326}

  describe "build/3" do
    test "is empty without points, even with tracked stations" do
      assert Filter.build([], ["K4GWA"], 25) == ""
    end

    test "emits one range term per distinct point, rounded and in a stable order" do
      points = [point(-77.6088, 43.1566), point(-77.6088, 43.1566), point(-78, 42)]

      assert Filter.build(points, [], 25) == "r/42.0/-78.0/25 r/43.157/-77.609/25"
    end

    test "emits an exact budlist term per tracked station, SSID included" do
      terms =
        Filter.build([point(-77.6088, 43.1566)], ["w2xyz-9", "K4GWA-4", "K4GWA-4", "N2ABC"], 10)

      assert terms == "r/43.157/-77.609/10 b/K4GWA-4 b/N2ABC b/W2XYZ-9"
    end

    test "drops call signs that could break the filter line" do
      terms = Filter.build([point(-77.6088, 43.1566)], ["BAD CALL", "N0;DROP", "W2/OK", ""], 10)

      assert terms == "r/43.157/-77.609/10"
    end
  end

  test "login_line/4 identifies the app and asks for the filter" do
    assert Filter.login_line("WB2EOC", "-1", "0.1.0", "r/43.157/-77.609/25") ==
             "user WB2EOC pass -1 vers mc_emcomm 0.1.0 filter r/43.157/-77.609/25\r\n"
  end

  test "filter_line/1 is the in-band filter command" do
    assert Filter.filter_line("r/43.157/-77.609/25 b/K4GWA-4") ==
             "#filter r/43.157/-77.609/25 b/K4GWA-4\r\n"
  end
end
