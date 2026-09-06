defmodule McEmcomm.MCP.Schemas do
  @moduledoc """
  JSON Schema fragments shared by the tools' `inputSchema` and
  `outputSchema` definitions, so the same record is described the same way
  everywhere (`McEmcomm.MCP.Tools.Present` produces the matching maps).
  """

  def id(description \\ "Record id."),
    do: %{"type" => "integer", "minimum" => 1, "description" => description}

  def string(description, opts \\ []) do
    %{"type" => "string", "description" => description}
    |> maybe_put("maxLength", opts[:max])
    |> maybe_put("minLength", opts[:min])
    |> maybe_put("enum", opts[:enum])
  end

  @doc """
  A value that may be `null`, expressed as `anyOf` single-type branches: the
  `type: [..., "null"]` array form is legal JSON Schema, but several MCP
  clients read `type` as one string and drop or reject the constraint.
  """
  def nullable(schema, description \\ nil) do
    %{"anyOf" => [Map.delete(schema, "description"), %{"type" => "null"}]}
    |> maybe_put("description", description || schema["description"])
  end

  def nullable_string(description), do: nullable(%{"type" => "string"}, description)

  def boolean(description), do: %{"type" => "boolean", "description" => description}

  def datetime(description),
    do: %{"type" => "string", "format" => "date-time", "description" => description}

  def nullable_datetime(description),
    do: nullable(%{"type" => "string", "format" => "date-time"}, description)

  def date(description),
    do: %{"type" => "string", "format" => "date", "description" => description}

  def nullable_date(description),
    do: nullable(%{"type" => "string", "format" => "date"}, description)

  def nullable_integer(description), do: nullable(%{"type" => "integer"}, description)

  def cursor, do: string("Opaque pagination cursor from a previous page's next_cursor.")

  def latitude,
    do: %{
      "type" => "number",
      "minimum" => -90,
      "maximum" => 90,
      "description" => "Latitude in degrees."
    }

  def longitude,
    do: %{
      "type" => "number",
      "minimum" => -180,
      "maximum" => 180,
      "description" => "Longitude in degrees."
    }

  @doc "A WGS 84 point as `{lat, lng}`."
  def point do
    %{
      "type" => "object",
      "properties" => %{"lat" => latitude(), "lng" => longitude()},
      "required" => ["lat", "lng"],
      "additionalProperties" => false
    }
  end

  def nullable_point, do: nullable(point(), "A WGS 84 point, or null when unknown.")

  def license_class do
    nullable(
      %{"type" => "string", "enum" => ~w(technician general amateur_extra advanced novice)},
      "FCC license class."
    )
  end

  def object(properties, required \\ []) do
    %{
      "type" => "object",
      "properties" => properties,
      "required" => required,
      "additionalProperties" => false
    }
  end

  @doc "An object schema for a tool that takes no arguments."
  def no_arguments, do: %{"type" => "object", "additionalProperties" => false}

  def array(items, description \\ nil) do
    %{"type" => "array", "items" => items} |> maybe_put("description", description)
  end

  @doc "A paginated list result: `items` plus `next_cursor`."
  def page(items_schema, key \\ "items") do
    object(
      %{
        key => array(items_schema),
        "next_cursor" =>
          nullable_string("Pass as `cursor` to fetch the next page; null on the last page.")
      },
      [key, "next_cursor"]
    )
  end

  ## Records

  def net do
    object(
      %{
        "id" => id("Net id."),
        "name" => string("Net name."),
        "aprs_keyword" => string("Word a station beacons to check in over APRS."),
        "started_at" => datetime("When the net started (UTC)."),
        "ended_at" => nullable_datetime("When the net ended; null while on the air."),
        "operation_id" => nullable_integer("Operation the net is assigned to, if any."),
        "net_control_member_id" => nullable_integer("Member acting as net control, if any."),
        "notes" => nullable_string("Free-text notes."),
        "on_air" => boolean("True while the net has not ended.")
      },
      ~w(id name aprs_keyword started_at ended_at operation_id net_control_member_id notes on_air)
    )
  end

  def checkin do
    object(
      %{
        "id" => id("Check-in id."),
        "net_id" => id("Net id."),
        "call_sign" => string("Station call sign, upper case."),
        "member_id" => nullable_integer("Matched member, if the call sign belongs to one."),
        "member_name" => nullable_string("Matched member's name, if any."),
        "location_name" => nullable_string("Snapshot label (QTH, APRS, or a named location)."),
        "location" => nullable_point(),
        "notes" => nullable_string("Operator notes."),
        "recorded_at" => datetime("When the station checked in (UTC)."),
        "ended_at" => nullable_datetime("When the station left; null while still on the net."),
        "aprs_station" => nullable_string("Full APRS station id (with SSID) when APRS-tracked.")
      },
      ~w(id net_id call_sign member_id member_name location_name location notes recorded_at ended_at aprs_station)
    )
  end

  def operation_location do
    object(
      %{
        "id" => id("Location id."),
        "name" => string("Location name, unique within the operation."),
        "location" => point(),
        "geofence_radius_m" => %{
          "type" => "integer",
          "minimum" => 1,
          "description" => "Geofence radius in meters."
        },
        "notes" => nullable_string("Notes."),
        "position" => %{"type" => "integer", "description" => "Display order."}
      },
      ~w(id name location geofence_radius_m notes position)
    )
  end

  def operation_attachment do
    object(
      %{
        "id" => id("Attachment id."),
        "filename" => string("Original file name."),
        "content_type" => string("MIME type."),
        "description" => string("Required description entered on upload.")
      },
      ~w(id filename content_type description)
    )
  end

  def attendance do
    object(
      %{
        "member_id" => id("Member id."),
        "member_name" => string("Member name."),
        "call_sign" => nullable_string("Member call sign."),
        "source" => string("How attendance was recorded.", enum: ~w(manual asset_checkin admin)),
        "recorded_at" => datetime("When attendance was recorded (UTC).")
      },
      ~w(member_id member_name call_sign source recorded_at)
    )
  end

  def operation_summary do
    object(
      %{
        "id" => id("Operation id."),
        "title" => string("Title."),
        "description" => nullable_string("Description."),
        "starts_at" => datetime("Start (UTC)."),
        "ends_at" => datetime("End (UTC)."),
        "visibility" => string("Who can see it on the website.", enum: ~w(public members))
      },
      ~w(id title description starts_at ends_at visibility)
    )
  end

  def operation do
    summary = operation_summary()

    %{
      summary
      | "properties" =>
          Map.merge(summary["properties"], %{
            "locations" => array(operation_location()),
            "attachments" => array(operation_attachment()),
            "attendance" => array(attendance())
          }),
        "required" => summary["required"] ++ ~w(locations attachments attendance)
    }
  end

  def member_summary do
    object(
      %{
        "id" => id("Member id."),
        "user_id" => id("Account id."),
        "name" => string("Name."),
        "call_sign" => nullable_string("Call sign."),
        "status" => string("Membership status.", enum: ~w(pending approved rejected inactive)),
        "license_class" => license_class(),
        "positions" => array(string("Leadership position name.")),
        "inserted_at" => datetime("When the profile was created (UTC).")
      },
      ~w(id user_id name call_sign status license_class positions inserted_at)
    )
  end

  def emergency_contact do
    nullable(
      object(
        %{
          "name" => string("Contact name."),
          "phone" => string("Contact phone."),
          "relation" => nullable_string("Relationship to the member.")
        },
        ~w(name phone relation)
      ),
      "Emergency contact, or null when none is recorded."
    )
  end

  def audit_entry do
    object(
      %{
        "from_status" => string("Status before."),
        "to_status" => string("Status after."),
        "reason" => nullable_string("Reason given, when one was required."),
        "at" => datetime("When (UTC).")
      },
      ~w(from_status to_status reason at)
    )
  end

  def member do
    summary = member_summary()

    %{
      summary
      | "properties" =>
          Map.merge(summary["properties"], %{
            "qth_address" => nullable_string("Home address (members and admins only)."),
            "qth" => nullable_point(),
            "emergency_contact" => emergency_contact(),
            "audit" => array(audit_entry(), "Status transitions, newest first.")
          }),
        "required" => summary["required"] ++ ~w(qth_address qth emergency_contact audit)
    }
  end

  def profile do
    object(
      %{
        "member_id" => id("Member id."),
        "name" => string("Name."),
        "call_sign" => nullable_string("Call sign."),
        "status" => string("Membership status.", enum: ~w(pending approved rejected inactive)),
        "license_class" => license_class(),
        "qth_address" => nullable_string("Home address."),
        "qth" => nullable_point(),
        "emergency_contact" => emergency_contact(),
        "positions" => array(string("Leadership position held.")),
        "admin" => boolean("Whether the account has administrator access."),
        "capabilities" =>
          array(object(%{"id" => id(), "name" => string("Capability.")}, ~w(id name))),
        "courses" =>
          array(
            object(
              %{
                "course_id" => id(),
                "name" => string("Course."),
                "completed_on" => nullable_date("Completion date."),
                "verified" => boolean("Verified by an administrator.")
              },
              ~w(course_id name completed_on verified)
            )
          ),
        "certifications" =>
          array(
            object(
              %{
                "certification_id" => id(),
                "name" => string("Certification."),
                "issued_on" => nullable_date("Issue date."),
                "expires_on" => nullable_date("Expiry date."),
                "verified" => boolean("Verified by an administrator.")
              },
              ~w(certification_id name issued_on expires_on verified)
            )
          )
      },
      ~w(member_id name call_sign status license_class qth_address qth emergency_contact positions admin capabilities courses certifications)
    )
  end

  def asset do
    object(
      %{
        "id" => id("Asset id."),
        "public_id" => string("Six-character id printed on the QR code."),
        "name" => string("Name."),
        "description" => nullable_string("Description."),
        "active" => boolean("Whether the asset is in service."),
        "sighting_url" => string("Public page the QR code opens.")
      },
      ~w(id public_id name description active sighting_url)
    )
  end

  def sighting do
    object(
      %{
        "id" => id("Sighting id."),
        "submitted_at" => datetime("When the form was submitted (UTC)."),
        "call_sign" => nullable_string("Call sign entered."),
        "note" => nullable_string("Note entered."),
        "claimed_responsibility" =>
          boolean("Whether the submitter took responsibility for the asset."),
        "verified" => boolean("Verified by an administrator."),
        "operation_id" => nullable_integer("Operation matched by geofence, if any.")
      },
      ~w(id submitted_at call_sign note claimed_responsibility verified operation_id)
    )
  end

  def catalog_item do
    object(
      %{
        "kind" => string("Catalog.", enum: ~w(capability course certification)),
        "id" => id("Item id."),
        "name" => string("Name."),
        "code" => nullable_string("Short code (e.g. IS-100)."),
        "description" => nullable_string("Description."),
        "active" => boolean("Whether the item is offered."),
        "prerequisite_course_id" => nullable_integer("Certifications only: required course."),
        "requires_task_book" => nullable(%{"type" => "boolean"}, "Certifications only.")
      },
      ~w(kind id name code description active prerequisite_course_id requires_task_book)
    )
  end

  def location do
    object(
      %{
        "id" => id("Location id."),
        "name" => string("Name."),
        "location" => point(),
        "position" => %{"type" => "integer", "description" => "Display order."}
      },
      ~w(id name location position)
    )
  end

  def document do
    object(
      %{
        "id" => id("Document id."),
        "title" => string("Title."),
        "filename" => string("File name."),
        "content_type" => string("MIME type."),
        "members_only" => boolean("Whether only members may download it."),
        "position" => %{"type" => "integer", "description" => "Display order."}
      },
      ~w(id title filename content_type members_only position)
    )
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
