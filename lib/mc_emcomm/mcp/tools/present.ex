defmodule McEmcomm.MCP.Tools.Present do
  @moduledoc """
  Serializers from context structs to the `structuredContent` maps described
  by `McEmcomm.MCP.Schemas`. Member PII beyond what the web UI shows the
  same tier never appears here: the member-tier views omit addresses,
  coordinates, and emergency contacts, and sightings use the member
  projection only (`McEmcomm.Sightings.list_for_asset_member_view/1`).
  """

  alias McEmcomm.Assets.Asset
  alias McEmcomm.Content.Document
  alias McEmcomm.Locations.DefaultLocation
  alias McEmcomm.Members.Member
  alias McEmcomm.Net.NetCheckin
  alias McEmcomm.Net.NetSession
  alias McEmcomm.Operations
  alias McEmcomm.Operations.Operation
  alias McEmcomm.Operations.OperationAttachment
  alias McEmcomm.Operations.OperationAttendance
  alias McEmcomm.Operations.OperationLocation
  alias McEmcomm.Operations.OperationRsvp

  def datetime(nil), do: nil
  def datetime(%DateTime{} = dt), do: DateTime.to_iso8601(dt)

  def date(nil), do: nil
  def date(%Date{} = d), do: Date.to_iso8601(d)

  def point(%Geo.Point{coordinates: {lng, lat}}), do: %{"lat" => lat, "lng" => lng}
  def point(_point), do: nil

  def net(%NetSession{} = net) do
    %{
      "id" => net.id,
      "name" => net.name,
      "aprs_keyword" => net.aprs_keyword,
      "started_at" => datetime(net.started_at),
      "ended_at" => datetime(net.ended_at),
      "operation_id" => net.operation_id,
      "net_control_member_id" => net.net_control_member_id,
      "notes" => net.notes,
      "on_air" => is_nil(net.ended_at)
    }
  end

  def checkin(%NetCheckin{} = checkin) do
    %{
      "id" => checkin.id,
      "net_id" => checkin.net_session_id,
      "call_sign" => checkin.call_sign,
      "member_id" => checkin.member_id,
      "member_name" => member_name(checkin.member),
      "location_name" => checkin.location_name,
      "location" => point(checkin.location_point),
      "notes" => checkin.notes,
      "recorded_at" => datetime(checkin.recorded_at),
      "ended_at" => datetime(checkin.ended_at),
      "aprs_station" => checkin.aprs_call_sign
    }
  end

  defp member_name(%Member{name: name}), do: name
  defp member_name(_member), do: nil

  def operation_summary(%Operation{} = op) do
    %{
      "id" => op.id,
      "title" => op.title,
      "description" => op.description,
      "starts_at" => datetime(op.starts_at),
      "ends_at" => datetime(op.ends_at),
      "visibility" => Atom.to_string(op.visibility)
    }
  end

  def operation(%Operation{} = op) do
    op
    |> operation_summary()
    |> Map.merge(%{
      "locations" => Enum.map(op.locations, &operation_location/1),
      "attachments" => Enum.map(op.attachments, &operation_attachment/1),
      "rsvps" => op.rsvps |> Operations.sort_rsvps() |> Enum.map(&rsvp/1),
      "attendance" => Enum.map(op.attendance, &attendance/1)
    })
  end

  def operation_location(%OperationLocation{} = location) do
    %{
      "id" => location.id,
      "name" => location.name,
      "location" => point(location.point),
      "geofence_radius_m" => location.geofence_radius_m,
      "notes" => location.notes,
      "position" => location.position
    }
  end

  def operation_attachment(%OperationAttachment{} = attachment) do
    %{
      "id" => attachment.id,
      "filename" => attachment.filename,
      "content_type" => attachment.content_type,
      "description" => attachment.description
    }
  end

  def rsvp(%OperationRsvp{member: %Member{} = member} = rsvp) do
    %{
      "member_id" => member.id,
      "member_name" => member.name,
      "call_sign" => member.call_sign,
      "response" => Atom.to_string(rsvp.response),
      "note" => rsvp.note,
      "responded_at" => datetime(rsvp.responded_at)
    }
  end

  def attendance(%OperationAttendance{member: %Member{} = member} = attendance) do
    %{
      "member_id" => member.id,
      "member_name" => member.name,
      "call_sign" => member.call_sign,
      "source" => Atom.to_string(attendance.source),
      "recorded_at" => datetime(attendance.recorded_at)
    }
  end

  def member_summary(%Member{} = member) do
    %{
      "id" => member.id,
      "user_id" => member.user_id,
      "name" => member.name,
      "call_sign" => member.call_sign,
      "status" => Atom.to_string(member.status),
      "license_class" => member.license_class && Atom.to_string(member.license_class),
      "positions" => positions(member),
      "inserted_at" => datetime(member.inserted_at)
    }
  end

  @doc "The administrator's view of a member: everything on `/admin/members`."
  def member(%Member{} = member, audit) do
    member
    |> member_summary()
    |> Map.merge(%{
      "qth_address" => member.qth_address,
      "qth" => point(member.qth_point),
      "emergency_contact" => emergency_contact(member),
      "audit" =>
        Enum.map(audit, fn entry ->
          %{
            "from_status" => entry.from_status,
            "to_status" => entry.to_status,
            "reason" => entry.reason,
            "at" => datetime(entry.inserted_at)
          }
        end)
    })
  end

  def emergency_contact(%Member{emergency_contact_name: nil, emergency_contact_phone: nil}),
    do: nil

  def emergency_contact(%Member{} = member) do
    %{
      "name" => member.emergency_contact_name,
      "phone" => member.emergency_contact_phone,
      "relation" => member.emergency_contact_relation
    }
  end

  defp positions(%Member{positions: positions}) when is_list(positions),
    do: Enum.map(positions, & &1.name)

  defp positions(_member), do: []

  def asset(%Asset{} = asset) do
    %{
      "id" => asset.id,
      "public_id" => asset.public_id,
      "name" => asset.name,
      "description" => asset.description,
      "active" => asset.active,
      "sighting_url" =>
        Application.fetch_env!(:mc_emcomm, :qr_base_url) <> "/a/#{asset.public_id}/s"
    }
  end

  @doc "A sighting from the member projection (no telemetry columns exist on it)."
  def sighting(sighting) do
    %{
      "id" => sighting.id,
      "submitted_at" => datetime(sighting.submitted_at),
      "call_sign" => sighting.call_sign,
      "note" => sighting.note,
      "claimed_responsibility" => sighting.claimed_responsibility,
      "verified" => sighting.verified,
      "operation_id" => sighting.operation_id
    }
  end

  def catalog_item(kind, item) do
    %{
      "kind" => kind,
      "id" => item.id,
      "name" => item.name,
      "code" => item.code,
      "description" => item.description,
      "active" => item.active,
      "prerequisite_course_id" => Map.get(item, :prerequisite_course_id),
      "requires_task_book" => Map.get(item, :requires_task_book)
    }
  end

  def location(%DefaultLocation{} = location) do
    %{
      "id" => location.id,
      "name" => location.name,
      "location" => point(location.point),
      "position" => location.position
    }
  end

  def document(%Document{} = document) do
    %{
      "id" => document.id,
      "title" => document.title,
      "filename" => document.filename,
      "content_type" => document.content_type,
      "members_only" => document.members_only,
      "position" => document.position
    }
  end
end
