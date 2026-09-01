defmodule McEmcomm.Locations do
  @moduledoc """
  Admin catalog of default locations: named map points (e.g. county rally
  points) selectable as the location snapshot of a net check-in.
  """

  import Ecto.Query, warn: false

  alias McEmcomm.Locations.DefaultLocation
  alias McEmcomm.Repo

  def list_default_locations do
    DefaultLocation
    |> order_by([l], asc: l.position, asc: l.name)
    |> Repo.all()
  end

  def get_default_location!(id), do: Repo.get!(DefaultLocation, id)

  def change_default_location(%DefaultLocation{} = location, attrs \\ %{}) do
    DefaultLocation.changeset(location, attrs)
  end

  def create_default_location(attrs) do
    %DefaultLocation{} |> DefaultLocation.changeset(attrs) |> Repo.insert()
  end

  def update_default_location(%DefaultLocation{} = location, attrs) do
    location |> DefaultLocation.changeset(attrs) |> Repo.update()
  end

  def delete_default_location(%DefaultLocation{} = location), do: Repo.delete(location)
end
