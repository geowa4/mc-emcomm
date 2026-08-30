defmodule McEmcomm.McEmcommFixtures do
  @moduledoc "Test helpers for the domain contexts (Members, Exercises, Assets, Sightings)."

  alias McEmcomm.Accounts.Scope
  alias McEmcomm.AccountsFixtures
  alias McEmcomm.Assets
  alias McEmcomm.Exercises
  alias McEmcomm.Members
  alias McEmcomm.Repo

  @doc "A user + approved member, plus the admin user who approved them."
  def member_fixture(attrs \\ %{}) do
    user = AccountsFixtures.user_fixture()

    admin =
      AccountsFixtures.user_fixture() |> Ecto.Changeset.change(is_admin: true) |> Repo.update!()

    {:ok, member} =
      Members.create_member(Map.merge(%{user_id: user.id, name: "Test Member"}, attrs))

    {:ok, member} = Members.transition_status(member, :approved, admin)
    %{member | user: user}
  end

  @doc "A user + pending member (not yet approved)."
  def pending_member_fixture(attrs \\ %{}) do
    user = AccountsFixtures.user_fixture()

    {:ok, member} =
      Members.create_member(Map.merge(%{user_id: user.id, name: "Pending Member"}, attrs))

    %{member | user: user}
  end

  @doc "A user with `is_admin: true`, wrapped in a scope."
  def admin_scope_fixture do
    user =
      AccountsFixtures.user_fixture() |> Ecto.Changeset.change(is_admin: true) |> Repo.update!()

    Scope.for_user(user)
  end

  def member_scope_fixture(attrs \\ %{}) do
    member = member_fixture(attrs)
    Scope.for_user(member.user)
  end

  def asset_fixture(attrs \\ %{}) do
    {:ok, asset} =
      Assets.create_asset(Map.merge(%{name: "Test Asset #{System.unique_integer()}"}, attrs))

    asset
  end

  @doc """
  An exercise with one location at `{lat, lng}` (default: Rochester, NY),
  active "now" (starts 1 hour ago, ends in 1 hour) unless overridden.
  """
  def exercise_fixture(attrs \\ %{}, location_attrs \\ %{}) do
    creator = AccountsFixtures.user_fixture()
    now = DateTime.utc_now()

    exercise_attrs =
      Map.merge(
        %{
          "title" => "Test Exercise #{System.unique_integer()}",
          "starts_at" => DateTime.add(now, -3600, :second),
          "ends_at" => DateTime.add(now, 3600, :second),
          "visibility" => "members",
          "created_by_id" => creator.id
        },
        attrs
      )

    location_attrs =
      Map.merge(
        %{
          "name" => "Primary Site",
          "point" => %Geo.Point{coordinates: {-77.6088, 43.1566}, srid: 4326},
          "geofence_radius_m" => 500
        },
        location_attrs
      )

    {:ok, exercise} = Exercises.create_exercise_with_locations(exercise_attrs, [location_attrs])
    exercise
  end
end
