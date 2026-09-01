defmodule McEmcomm.McEmcommFixtures do
  @moduledoc "Test helpers for the domain contexts (Members, Operations, Assets, Sightings)."

  alias McEmcomm.Accounts.Scope
  alias McEmcomm.AccountsFixtures
  alias McEmcomm.Assets
  alias McEmcomm.Capabilities
  alias McEmcomm.Certifications
  alias McEmcomm.Content
  alias McEmcomm.Courses
  alias McEmcomm.Members
  alias McEmcomm.Net
  alias McEmcomm.Operations
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
  An operation with one location at `{lat, lng}` (default: Rochester, NY),
  active "now" (starts 1 hour ago, ends in 1 hour) unless overridden.
  """
  def operation_fixture(attrs \\ %{}, location_attrs \\ %{}) do
    creator = AccountsFixtures.user_fixture()
    now = DateTime.utc_now()

    operation_attrs =
      Map.merge(
        %{
          "title" => "Test Operation #{System.unique_integer()}",
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

    {:ok, operation} =
      Operations.create_operation_with_locations(operation_attrs, [location_attrs])

    operation
  end

  def document_fixture(attrs \\ %{}) do
    {:ok, document} =
      Content.create_document(
        Map.merge(
          %{
            title: "Test Document #{System.unique_integer()}",
            key: "documents/test-#{System.unique_integer()}.pdf",
            filename: "test.pdf",
            content_type: "application/pdf"
          },
          attrs
        )
      )

    document
  end

  def position_fixture(attrs \\ %{}) do
    {:ok, position} =
      Members.create_position(
        Map.merge(
          %{
            name: "Test Position #{System.unique_integer()}",
            sort_order: System.unique_integer([:positive, :monotonic])
          },
          attrs
        )
      )

    position
  end

  def capability_fixture(attrs \\ %{}) do
    {:ok, capability} =
      Capabilities.create_capability(
        Map.merge(%{name: "Test Capability #{System.unique_integer()}"}, attrs)
      )

    capability
  end

  def course_fixture(attrs \\ %{}) do
    {:ok, course} =
      Courses.create_course(Map.merge(%{name: "Test Course #{System.unique_integer()}"}, attrs))

    course
  end

  def certification_fixture(attrs \\ %{}) do
    {:ok, certification} =
      Certifications.create_certification(
        Map.merge(%{name: "Test Certification #{System.unique_integer()}"}, attrs)
      )

    certification
  end

  def net_session_fixture(member) do
    {:ok, session} = Net.start_session(member, %{"name" => "Test Net #{System.unique_integer()}"})
    session
  end
end
