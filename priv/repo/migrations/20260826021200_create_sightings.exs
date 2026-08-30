defmodule McEmcomm.Repo.Migrations.CreateSightings do
  use Ecto.Migration

  def change do
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
      add :exercise_id, references(:exercises, on_delete: :nilify_all)
      add :exercise_location_id, references(:exercise_locations, on_delete: :nilify_all)

      # Retention
      add :scrubbed_at, :utc_datetime_usec

      timestamps(type: :utc_datetime)
    end

    create index(:sightings, [:asset_id])
    create index(:sightings, [:member_id])
    create index(:sightings, [:exercise_id])
    create index(:sightings, [:session_token])
    create index(:sightings, [:visited_at])
    create index(:sightings, [:point], using: :gist)
  end
end
