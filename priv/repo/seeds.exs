# Idempotent development seeds (spec §19). Safe to run repeatedly:
#
#     mix run priv/repo/seeds.exs

alias McEmcomm.Repo
alias McEmcomm.Accounts
alias McEmcomm.Accounts.User
alias McEmcomm.Members
alias McEmcomm.Capabilities
alias McEmcomm.Courses
alias McEmcomm.Certifications
alias McEmcomm.Assets
alias McEmcomm.Exercises

seed_password = "seed-password-12345"

get_or_create_user = fn email, is_admin? ->
  case Repo.get_by(User, email: email) do
    nil ->
      {:ok, user} = Accounts.register_user(%{email: email})
      {:ok, {user, _tokens}} = Accounts.update_user_password(user, %{password: seed_password})

      user =
        user
        |> Ecto.Changeset.change(confirmed_at: DateTime.utc_now(:second), is_admin: is_admin?)
        |> Repo.update!()

      user

    user ->
      user
  end
end

get_or_create_member = fn user, attrs ->
  case Members.get_member_by_user_id(user.id) do
    nil ->
      {:ok, member} = Members.create_member(Map.put(attrs, :user_id, user.id))
      member

    member ->
      member
  end
end

approve = fn member, actor ->
  case member.status do
    :pending ->
      {:ok, member} = Members.transition_status(member, :approved, actor)
      member

    _ ->
      member
  end
end

# ## Admin + members across positions and quadrants
#
# All people are fictional analogues that mirror the real roster's *shape*
# (every filled position, including one person holding Vice-President and
# Emergency Coordinator at once). Real people are entered in production via
# the admin UI, never seeded.

admin_user = get_or_create_user.("admin@monroecountyemcomm.org", true)

admin_member =
  get_or_create_member.(admin_user, %{name: "Alex Rivera", call_sign: "W2ADM", quadrant: :NE})
  |> then(&approve.(&1, admin_user))

member_specs = [
  %{
    email: "president@monroecountyemcomm.org",
    name: "Jordan Blake",
    call_sign: "W2PRE",
    positions: ["President"],
    quadrant: :NE
  },
  %{
    email: "vice-president@monroecountyemcomm.org",
    name: "Devon Marsh",
    call_sign: "W2VEC",
    positions: ["Vice-President", "Emergency Coordinator"],
    quadrant: :SE
  },
  %{
    email: "secretary@monroecountyemcomm.org",
    name: "Sam Okafor",
    call_sign: "W2SEC",
    positions: ["Secretary"],
    quadrant: :NW
  },
  %{
    email: "treasurer@monroecountyemcomm.org",
    name: "Casey Nguyen",
    call_sign: "W2TRE",
    positions: ["Treasurer"],
    quadrant: :SE
  },
  %{
    email: "director1@monroecountyemcomm.org",
    name: "Rowan Ellis",
    call_sign: "W2DL1",
    positions: ["Director-at-Large 1"],
    quadrant: :NW
  },
  %{
    email: "director2@monroecountyemcomm.org",
    name: "Harper Quinn",
    call_sign: "W2DL2",
    positions: ["Director-at-Large 2"],
    quadrant: :SW
  },
  %{
    email: "member1@monroecountyemcomm.org",
    name: "Riley Thompson",
    call_sign: "W2ME1",
    positions: [],
    quadrant: :SW
  },
  %{
    email: "member2@monroecountyemcomm.org",
    name: "Morgan Alvarez",
    call_sign: "W2ME2",
    positions: [],
    quadrant: :out_of_county
  },
  %{
    email: "pending@monroecountyemcomm.org",
    name: "Taylor Kim",
    call_sign: "W2PND",
    positions: [],
    quadrant: :NE,
    skip_approval: true
  }
]

# The positions table ships empty (admins manage it at /admin/positions);
# seed the catalog the member specs above reference.
position_specs = [
  {"President", 1},
  {"Vice-President", 2},
  {"Secretary", 3},
  {"Treasurer", 4},
  {"Emergency Coordinator", 5},
  {"Assistant Emergency Coordinator", 6},
  {"Director-at-Large 1", 7},
  {"Director-at-Large 2", 8},
  {"Director-at-Large 3", 9}
]

for {name, sort_order} <- position_specs do
  case Repo.get_by(McEmcomm.Members.Position, name: name) do
    nil ->
      {:ok, _} = Members.create_position(%{name: name, sort_order: sort_order})

    _position ->
      :ok
  end
end

position_ids_by_name =
  McEmcomm.Members.Position
  |> Repo.all()
  |> Map.new(&{&1.name, &1.id})

set_positions = fn member, position_names ->
  ids = Enum.map(position_names, &Map.fetch!(position_ids_by_name, &1))
  {:ok, member} = Members.update_member_positions(member, ids)
  member
end

# The admin covers the third Director-at-Large seat; Assistant Emergency
# Coordinator is deliberately vacant (as in the real roster) so the public
# About page exercises its "Vacant" rendering.
set_positions.(admin_member, ["Director-at-Large 3"])

members =
  Enum.map(member_specs, fn spec ->
    user = get_or_create_user.(spec.email, false)
    member = get_or_create_member.(user, Map.take(spec, [:name, :call_sign, :quadrant]))
    member = if spec[:skip_approval], do: member, else: approve.(member, admin_user)
    set_positions.(member, spec.positions)
  end)

# ## Capabilities catalog

capabilities = ["2m/70cm HT (field-programmable)", "APRS", "HF voice"]

Enum.each(capabilities, fn name ->
  unless Repo.get_by(Capabilities.Capability, name: name) do
    {:ok, _} = Capabilities.create_capability(%{name: name})
  end
end)

# ## Courses catalog

courses = [
  %{name: "AUXCOMM", code: "AUXCOMM"},
  %{name: "Introduction to the Incident Command System", code: "IS-100"},
  %{name: "Basic Incident Command System for Initial Response", code: "IS-200"},
  %{name: "An Introduction to the National Incident Management System", code: "IS-700"},
  %{name: "National Response Framework, An Introduction", code: "IS-800"}
]

Enum.each(courses, fn attrs ->
  unless Repo.get_by(Courses.Course, name: attrs.name) do
    {:ok, _} = Courses.create_course(attrs)
  end
end)

auxcomm_course = Repo.get_by!(Courses.Course, name: "AUXCOMM")

# ## Certifications catalog

certifications = [
  %{
    name: "AUXC",
    code: "AUXC",
    prerequisite_course_id: auxcomm_course.id,
    requires_task_book: true
  },
  %{name: "COML", code: "COML", requires_task_book: true},
  %{name: "COMT", code: "COMT", requires_task_book: true}
]

Enum.each(certifications, fn attrs ->
  unless Repo.get_by(Certifications.Certification, name: attrs.name) do
    {:ok, _} = Certifications.create_certification(attrs)
  end
end)

# ## Exercises: one single-location, one multi-location

unless Repo.get_by(Exercises.Exercise, title: "Spring Field Day Drill") do
  {:ok, _} =
    Exercises.create_exercise_with_locations(
      %{
        "title" => "Spring Field Day Drill",
        "description" => "Single-site exercise at the EOC.",
        "starts_at" => DateTime.utc_now() |> DateTime.add(7, :day),
        "ends_at" => DateTime.utc_now() |> DateTime.add(7, :day) |> DateTime.add(4, :hour),
        "visibility" => "members",
        "created_by_id" => admin_user.id
      },
      [
        %{
          "point" => %Geo.Point{coordinates: {-77.6088, 43.1566}, srid: 4326},
          "geofence_radius_m" => 500
        }
      ]
    )
end

unless Repo.get_by(Exercises.Exercise, title: "County-Wide Simulated Emergency Test") do
  {:ok, _} =
    Exercises.create_exercise_with_locations(
      %{
        "title" => "County-Wide Simulated Emergency Test",
        "description" => "Multi-site SET exercise across Monroe County.",
        "starts_at" => DateTime.utc_now() |> DateTime.add(30, :day),
        "ends_at" => DateTime.utc_now() |> DateTime.add(30, :day) |> DateTime.add(6, :hour),
        "visibility" => "public",
        "created_by_id" => admin_user.id
      },
      [
        %{
          "name" => "EOC",
          "point" => %Geo.Point{coordinates: {-77.6088, 43.1566}, srid: 4326},
          "geofence_radius_m" => 300
        },
        %{
          "name" => "Cobbs Hill Repeater Site",
          "point" => %Geo.Point{coordinates: {-77.5675, 43.1355}, srid: 4326},
          "geofence_radius_m" => 200
        },
        %{
          "name" => "West Irondequoit Shelter",
          "point" => %Geo.Point{coordinates: {-77.5691, 43.2081}, srid: 4326},
          "geofence_radius_m" => 250
        }
      ]
    )
end

# ## Sample assets

assets = ["Field Go-Kit #1", "Repeater Trailer", "APRS Tracker Unit"]

Enum.each(assets, fn name ->
  unless Repo.get_by(Assets.Asset, name: name) do
    {:ok, _} = Assets.create_asset(%{name: name, description: "Seed asset: #{name}"})
  end
end)

IO.puts("""
Seeds complete.
  Admin login: #{admin_user.email} / #{seed_password}
  Members: #{Enum.count(members) + 1} (including admin)
""")
