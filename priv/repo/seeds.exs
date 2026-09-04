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
alias McEmcomm.Locations
alias McEmcomm.Operations

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

# ## Admin + members across positions
#
# All people are fictional analogues that mirror the real roster's *shape*
# (every filled position, including one person holding Vice-President and
# Emergency Coordinator at once). Real people are entered in production via
# the admin UI, never seeded. QTH points are fictional spots spread around
# Monroe County so nets and the on-net map have something to show.

set_qth = fn member, {lng, lat} ->
  {:ok, member} =
    Members.update_profile(member, %{
      qth_point: %Geo.Point{coordinates: {lng, lat}, srid: 4326}
    })

  member
end

admin_user = get_or_create_user.("admin@monroecountyemcomm.org", true)

admin_member =
  get_or_create_member.(admin_user, %{name: "Alex Rivera", call_sign: "W2ADM"})
  |> then(&approve.(&1, admin_user))
  |> then(&set_qth.(&1, {-77.5895, 43.2001}))

# One seeded emergency contact (fictional, 555 number) so the admin members
# page has something to render in that column.
{:ok, admin_member} =
  Members.update_profile(admin_member, %{
    emergency_contact_name: "Casey Rivera",
    emergency_contact_phone: "585-555-0142",
    emergency_contact_relation: "Spouse"
  })

member_specs = [
  %{
    email: "president@monroecountyemcomm.org",
    name: "Jordan Blake",
    call_sign: "W2PRE",
    positions: ["President"],
    qth: {-77.5341, 43.2154}
  },
  %{
    email: "vice-president@monroecountyemcomm.org",
    name: "Devon Marsh",
    call_sign: "W2VEC",
    positions: ["Vice-President", "Emergency Coordinator"],
    qth: {-77.4459, 43.0912}
  },
  %{
    email: "secretary@monroecountyemcomm.org",
    name: "Sam Okafor",
    call_sign: "W2SEC",
    positions: ["Secretary"],
    qth: {-77.7312, 43.1888}
  },
  %{
    email: "treasurer@monroecountyemcomm.org",
    name: "Casey Nguyen",
    call_sign: "W2TRE",
    positions: ["Treasurer"],
    qth: {-77.5122, 43.0987}
  },
  %{
    email: "director1@monroecountyemcomm.org",
    name: "Rowan Ellis",
    call_sign: "W2DL1",
    positions: ["Director-at-Large 1"],
    qth: {-77.6931, 43.2143}
  },
  %{
    email: "director2@monroecountyemcomm.org",
    name: "Harper Quinn",
    call_sign: "W2DL2",
    positions: ["Director-at-Large 2"],
    qth: {-77.7423, 43.0341}
  },
  %{
    email: "member1@monroecountyemcomm.org",
    name: "Riley Thompson",
    call_sign: "W2ME1",
    positions: [],
    qth: {-77.6512, 43.0455}
  },
  %{
    email: "member2@monroecountyemcomm.org",
    name: "Morgan Alvarez",
    call_sign: "W2ME2",
    positions: [],
    # Out of county, west of Batavia.
    qth: {-78.2519, 42.9987}
  },
  %{
    email: "pending@monroecountyemcomm.org",
    name: "Taylor Kim",
    call_sign: "W2PND",
    positions: [],
    skip_approval: true
  }
]

# The positions table ships empty (admins manage it at /admin/positions);
# seed the catalog the member specs above reference. The Secretary is flagged
# to receive new-member notices so a seeded registration + confirmation shows
# the email in /dev/mailbox.
position_specs = [
  {"President", 1, false},
  {"Vice-President", 2, false},
  {"Secretary", 3, true},
  {"Treasurer", 4, false},
  {"Emergency Coordinator", 5, false},
  {"Assistant Emergency Coordinator", 6, false},
  {"Director-at-Large 1", 7, false},
  {"Director-at-Large 2", 8, false},
  {"Director-at-Large 3", 9, false}
]

for {name, sort_order, notify} <- position_specs do
  case Repo.get_by(McEmcomm.Members.Position, name: name) do
    nil ->
      {:ok, _} =
        Members.create_position(%{
          name: name,
          sort_order: sort_order,
          notify_on_new_member: notify
        })

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
# About page operations its "Vacant" rendering.
set_positions.(admin_member, ["Director-at-Large 3"])

members =
  Enum.map(member_specs, fn spec ->
    user = get_or_create_user.(spec.email, false)
    member = get_or_create_member.(user, Map.take(spec, [:name, :call_sign]))
    member = if spec[:skip_approval], do: member, else: approve.(member, admin_user)
    member = if spec[:qth], do: set_qth.(member, spec.qth), else: member
    set_positions.(member, spec.positions)
  end)

# ## Capabilities catalog

capabilities = [
  %{
    name: "2m/70cm HT (field-programmable)",
    description:
      "A dual-band handheld you can reprogram in the field without a computer, for simplex and repeater nets at a deployment site."
  },
  %{
    name: "APRS",
    description:
      "Automatic Packet Reporting System: you can send position beacons and short text messages over VHF packet."
  },
  %{
    name: "HF voice",
    description:
      "An HF station and the license privileges to work voice on regional and statewide nets when repeaters are down."
  }
]

Enum.each(capabilities, fn attrs ->
  case Repo.get_by(Capabilities.Capability, name: attrs.name) do
    nil -> {:ok, _} = Capabilities.create_capability(attrs)
    capability -> {:ok, _} = Capabilities.update_capability(capability, attrs)
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

# ## Operations: one single-location, one multi-location

unless Repo.get_by(Operations.Operation, title: "Spring Field Day Drill") do
  {:ok, _} =
    Operations.create_operation_with_locations(
      %{
        "title" => "Spring Field Day Drill",
        "description" => "Single-site operation at the EOC.",
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

unless Repo.get_by(Operations.Operation, title: "County-Wide Simulated Emergency Test") do
  {:ok, _} =
    Operations.create_operation_with_locations(
      %{
        "title" => "County-Wide Simulated Emergency Test",
        "description" => "Multi-site SET operation across Monroe County.",
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

# ## Default locations
#
# The four county quadrant rally points admins would otherwise create at
# /admin/locations. Coordinates are fictional spots inside each quadrant.

default_location_specs = [
  {"NW", {-77.7318, 43.2205}, 1},
  {"NE", {-77.5013, 43.2312}, 2},
  {"SW", {-77.7401, 43.0288}, 3},
  {"SE", {-77.4922, 43.0411}, 4}
]

for {name, {lng, lat}, position} <- default_location_specs do
  unless Repo.get_by(Locations.DefaultLocation, name: name) do
    {:ok, _} =
      Locations.create_default_location(%{
        name: name,
        point: %Geo.Point{coordinates: {lng, lat}, srid: 4326},
        position: position
      })
  end
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
