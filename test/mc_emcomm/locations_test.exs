defmodule McEmcomm.LocationsTest do
  use McEmcomm.DataCase, async: true

  alias McEmcomm.Locations
  alias McEmcomm.McEmcommFixtures

  test "create requires a name and a point" do
    assert {:error, changeset} = Locations.create_default_location(%{})
    assert %{name: ["can't be blank"], point: ["can't be blank"]} = errors_on(changeset)
  end

  test "names are unique case-insensitively" do
    McEmcommFixtures.default_location_fixture(%{name: "NW"})

    assert {:error, changeset} =
             Locations.create_default_location(%{name: "nw", point: McEmcommFixtures.geo_point()})

    assert %{name: ["has already been taken"]} = errors_on(changeset)
  end

  test "list orders by position then name" do
    McEmcommFixtures.default_location_fixture(%{name: "SE", position: 2})
    McEmcommFixtures.default_location_fixture(%{name: "NW", position: 1})
    McEmcommFixtures.default_location_fixture(%{name: "NE", position: 1})

    assert ["NE", "NW", "SE"] = Locations.list_default_locations() |> Enum.map(& &1.name)
  end

  test "update and delete round-trip" do
    location = McEmcommFixtures.default_location_fixture(%{name: "EOC"})

    {:ok, updated} = Locations.update_default_location(location, %{name: "Backup EOC"})
    assert Locations.get_default_location!(location.id).name == "Backup EOC"

    {:ok, _} = Locations.delete_default_location(updated)
    assert Locations.list_default_locations() == []
  end
end
