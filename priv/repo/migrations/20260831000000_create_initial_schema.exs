defmodule McEmcomm.Repo.Migrations.CreateInitialSchema do
  use Ecto.Migration

  # Baseline migration for a fresh install. The app had no deployments when
  # the pre-launch migration history was squashed into this file, so the
  # schema is created directly in its intended shape (leadership positions
  # are relational; there is no members.role column). Every position is
  # single-holder, enforced by the unique index on member_positions.position_id.
  # The positions table starts empty: admins manage the catalog at
  # /admin/positions, and dev data comes from seeds.exs.

  def change do
    execute "CREATE EXTENSION IF NOT EXISTS citext", ""
    execute "CREATE EXTENSION IF NOT EXISTS postgis", ""

    # ## Accounts

    create table(:users) do
      add :email, :citext, null: false
      add :hashed_password, :string
      add :confirmed_at, :utc_datetime
      add :is_admin, :boolean, null: false, default: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:users, [:email])

    create table(:users_tokens) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :token, :binary, null: false
      add :context, :string, null: false
      add :sent_to, :string
      add :authenticated_at, :utc_datetime

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:users_tokens, [:user_id])
    create unique_index(:users_tokens, [:context, :token])

    # ## Inbound webhooks

    create table(:webhook_events) do
      add :svix_id, :string, null: false
      add :event_type, :string
      timestamps(type: :utc_datetime, updated_at: false)
    end

    create unique_index(:webhook_events, [:svix_id])

    # ## Members & leadership positions

    create table(:members) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :call_sign, :citext
      add :name, :string, null: false
      add :qth_address, :text
      add :qth_point, :"geography(Point,4326)"
      add :quadrant, :string
      add :license_class, :string
      add :status, :string, null: false, default: "pending"

      timestamps(type: :utc_datetime)
    end

    create unique_index(:members, [:user_id])

    create unique_index(:members, [:call_sign],
             name: :members_call_sign_index,
             where: "call_sign IS NOT NULL"
           )

    create index(:members, [:qth_point], using: :gist)
    create index(:members, [:status])

    create table(:positions) do
      add :name, :string, null: false
      add :sort_order, :integer, null: false
      add :grants_admin, :boolean, null: false, default: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:positions, [:name])
    create unique_index(:positions, [:sort_order])
    create constraint(:positions, :sort_order_positive, check: "sort_order > 0")

    create table(:member_positions) do
      add :member_id, references(:members, on_delete: :delete_all), null: false
      add :position_id, references(:positions, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:member_positions, [:position_id])
    create index(:member_positions, [:member_id])

    create table(:membership_audit) do
      add :member_id, references(:members, on_delete: :delete_all), null: false
      add :actor_user_id, references(:users, on_delete: :nothing), null: false
      add :from_status, :string, null: false
      add :to_status, :string, null: false
      add :reason, :text

      add :inserted_at, :utc_datetime_usec, null: false, default: fragment("now()")
    end

    create index(:membership_audit, [:member_id])

    # ## Capabilities

    create table(:capabilities) do
      add :name, :citext, null: false
      add :code, :string
      add :description, :text
      add :active, :boolean, null: false, default: true

      timestamps(type: :utc_datetime)
    end

    create unique_index(:capabilities, [:name])

    create table(:member_capabilities) do
      add :member_id, references(:members, on_delete: :delete_all), null: false
      add :capability_id, references(:capabilities, on_delete: :delete_all), null: false
      add :notes, :text

      timestamps(type: :utc_datetime)
    end

    create unique_index(:member_capabilities, [:member_id, :capability_id])

    # ## Courses & certifications

    create table(:courses) do
      add :name, :citext, null: false
      add :code, :string
      add :description, :text
      add :active, :boolean, null: false, default: true

      timestamps(type: :utc_datetime)
    end

    create unique_index(:courses, [:name])

    create table(:member_courses) do
      add :member_id, references(:members, on_delete: :delete_all), null: false
      add :course_id, references(:courses, on_delete: :delete_all), null: false
      add :completed_on, :date
      add :evidence_key, :string
      add :evidence_filename, :string
      add :evidence_content_type, :string
      add :verified, :boolean, null: false, default: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:member_courses, [:member_id, :course_id])

    create table(:certifications) do
      add :name, :citext, null: false
      add :code, :string
      add :description, :text
      add :prerequisite_course_id, references(:courses, on_delete: :nilify_all)
      add :requires_task_book, :boolean, null: false, default: true
      add :active, :boolean, null: false, default: true

      timestamps(type: :utc_datetime)
    end

    create unique_index(:certifications, [:name])
    create index(:certifications, [:prerequisite_course_id])

    create table(:member_certifications) do
      add :member_id, references(:members, on_delete: :delete_all), null: false
      add :certification_id, references(:certifications, on_delete: :delete_all), null: false
      add :issued_on, :date
      add :expires_on, :date
      add :task_book_key, :string
      add :task_book_filename, :string
      add :task_book_content_type, :string
      add :certificate_key, :string
      add :certificate_filename, :string
      add :certificate_content_type, :string
      add :verified, :boolean, null: false, default: false
      add :notes, :text

      timestamps(type: :utc_datetime)
    end

    create unique_index(:member_certifications, [:member_id, :certification_id])

    # ## Assets

    create table(:assets) do
      add :public_id, :char, size: 6, null: false
      add :name, :string, null: false
      add :description, :text
      add :image_key, :string
      add :image_filename, :string
      add :image_content_type, :string
      add :active, :boolean, null: false, default: true

      timestamps(type: :utc_datetime)
    end

    create unique_index(:assets, [:public_id])

    # ## Operations

    create table(:operations) do
      add :title, :string, null: false
      add :description, :text
      add :starts_at, :utc_datetime, null: false
      add :ends_at, :utc_datetime, null: false
      add :visibility, :string, null: false, default: "members"
      add :created_by_id, references(:users, on_delete: :nothing), null: false

      timestamps(type: :utc_datetime)
    end

    create constraint(:operations, :ends_at_after_starts_at, check: "ends_at > starts_at")
    create index(:operations, [:starts_at])
    create index(:operations, [:visibility])

    create table(:operation_locations) do
      add :operation_id, references(:operations, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :point, :"geography(Point,4326)", null: false
      add :geofence_radius_m, :integer, null: false, default: 500
      add :notes, :text
      add :position, :integer, null: false, default: 0

      timestamps(type: :utc_datetime)
    end

    create index(:operation_locations, [:operation_id])
    create index(:operation_locations, [:point], using: :gist)
    create unique_index(:operation_locations, [:operation_id, :name])

    # ## Sightings

    create table(:sightings) do
      # Identity and visit (update point 0, HTTP mount)
      add :asset_id, references(:assets, on_delete: :delete_all), null: false
      add :session_token, :string, null: false
      add :visited_at, :utc_datetime_usec, null: false
      add :remote_ip, :inet
      add :fly_region, :string
      add :user_agent, :text
      add :sec_ch_ua, :string
      add :sec_ch_ua_platform, :string
      add :sec_ch_ua_mobile, :string
      add :accept_language, :string
      add :referer, :text
      add :browser_name, :string
      add :browser_version, :string
      add :os_name, :string
      add :os_version, :string
      add :device_type, :string

      # Client environment (update point 1, socket connect)
      add :connected_at, :utc_datetime_usec
      add :timezone, :string
      add :screen_w, :integer
      add :screen_h, :integer
      add :device_pixel_ratio, :float
      add :languages, {:array, :string}
      add :connection_type, :string
      add :touch, :boolean

      # Geolocation (update point 1, after permission)
      add :located_at, :utc_datetime_usec
      add :point, :"geography(Point,4326)"
      add :accuracy, :float
      add :altitude, :float
      add :heading, :float
      add :speed, :float
      add :geo_denied, :boolean, null: false, default: false

      # Submission (update point 2, form submit)
      add :submitted_at, :utc_datetime_usec
      add :call_sign, :citext
      add :member_id, references(:members, on_delete: :nilify_all)
      add :claimed_responsibility, :boolean, null: false, default: false
      add :note, :text
      add :verified, :boolean, null: false, default: false
      add :operation_id, references(:operations, on_delete: :nilify_all)
      add :operation_location_id, references(:operation_locations, on_delete: :nilify_all)

      # Retention
      add :scrubbed_at, :utc_datetime_usec

      timestamps(type: :utc_datetime)
    end

    create index(:sightings, [:asset_id])
    create index(:sightings, [:member_id])
    create index(:sightings, [:operation_id])
    create index(:sightings, [:session_token])
    create index(:sightings, [:visited_at])
    create index(:sightings, [:point], using: :gist)

    create table(:operation_attachments) do
      add :operation_id, references(:operations, on_delete: :delete_all), null: false
      add :key, :string, null: false
      add :filename, :string, null: false
      add :content_type, :string, null: false
      add :description, :text, null: false
      add :uploaded_by_id, references(:users, on_delete: :nothing), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:operation_attachments, [:operation_id])

    create constraint(:operation_attachments, :description_not_empty,
             check: "length(btrim(description)) > 0"
           )

    create table(:operation_attendance) do
      add :operation_id, references(:operations, on_delete: :delete_all), null: false
      add :member_id, references(:members, on_delete: :delete_all), null: false
      add :source, :string, null: false
      add :sighting_id, references(:sightings, on_delete: :nilify_all)
      add :recorded_at, :utc_datetime_usec, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:operation_attendance, [:operation_id, :member_id])

    # ## Nets

    create table(:net_sessions) do
      add :started_by_member_id, references(:members, on_delete: :nothing), null: false
      add :name, :string
      add :started_at, :utc_datetime, null: false
      add :ended_at, :utc_datetime
      add :notes, :text

      timestamps(type: :utc_datetime)
    end

    create index(:net_sessions, [:started_at])

    create table(:net_checkins) do
      add :net_session_id, references(:net_sessions, on_delete: :delete_all), null: false
      add :call_sign, :citext, null: false
      add :member_id, references(:members, on_delete: :nilify_all)
      add :quadrant, :string
      add :notes, :text
      add :recorded_at, :utc_datetime_usec, null: false
      add :ended_at, :utc_datetime_usec

      timestamps(type: :utc_datetime)
    end

    create index(:net_checkins, [:net_session_id])
    create index(:net_checkins, [:member_id])

    # ## Documents

    create table(:documents) do
      add :title, :string, null: false
      add :key, :string, null: false
      add :filename, :string, null: false
      add :content_type, :string, null: false
      add :members_only, :boolean, null: false, default: true
      add :active, :boolean, null: false, default: true
      add :position, :integer, null: false, default: 0

      timestamps(type: :utc_datetime)
    end
  end
end
