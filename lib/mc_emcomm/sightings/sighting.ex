defmodule McEmcomm.Sightings.Sighting do
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  schema "sightings" do
    # Identity and visit (update point 0, HTTP mount)
    field :session_token, :string
    field :visited_at, :utc_datetime_usec
    field :remote_ip, EctoNetwork.INET
    field :fly_region, :string
    field :user_agent, :string
    field :sec_ch_ua, :string
    field :sec_ch_ua_platform, :string
    field :sec_ch_ua_mobile, :string
    field :accept_language, :string
    field :referer, :string
    field :browser_name, :string
    field :browser_version, :string
    field :os_name, :string
    field :os_version, :string
    field :device_type, :string

    # Client environment (update point 1, socket connect)
    field :connected_at, :utc_datetime_usec
    field :timezone, :string
    field :screen_w, :integer
    field :screen_h, :integer
    field :device_pixel_ratio, :float
    field :languages, {:array, :string}
    field :connection_type, :string
    field :touch, :boolean

    # Geolocation (update point 1, after permission)
    field :located_at, :utc_datetime_usec
    field :point, Geo.PostGIS.Geometry
    field :accuracy, :float
    field :altitude, :float
    field :heading, :float
    field :speed, :float
    field :geo_denied, :boolean, default: false

    # Submission (update point 2, form submit)
    field :submitted_at, :utc_datetime_usec
    field :call_sign, :string
    field :claimed_responsibility, :boolean, default: false
    field :note, :string
    field :verified, :boolean, default: false

    # Retention
    field :scrubbed_at, :utc_datetime_usec

    belongs_to :asset, McEmcomm.Assets.Asset
    belongs_to :member, McEmcomm.Members.Member
    belongs_to :exercise, McEmcomm.Exercises.Exercise
    belongs_to :exercise_location, McEmcomm.Exercises.ExerciseLocation

    timestamps(type: :utc_datetime)
  end

  @visit_fields ~w(asset_id session_token visited_at remote_ip fly_region user_agent
                    sec_ch_ua sec_ch_ua_platform sec_ch_ua_mobile accept_language referer
                    browser_name browser_version os_name os_version device_type)a

  @doc "Update point 0 — HTTP mount, before the socket connects."
  def visit_changeset(sighting, attrs) do
    sighting
    |> cast(attrs, @visit_fields)
    |> validate_required([:asset_id, :session_token, :visited_at])
    |> foreign_key_constraint(:asset_id)
  end

  @client_env_fields ~w(connected_at timezone screen_w screen_h device_pixel_ratio
                         languages connection_type touch)a

  @doc "Update point 1a — socket connect, client environment."
  def client_env_changeset(sighting, attrs) do
    cast(sighting, attrs, @client_env_fields)
  end

  @geolocation_fields ~w(located_at point accuracy altitude heading speed geo_denied)a

  @doc "Update point 1b — geolocation grant/deny."
  def geolocation_changeset(sighting, attrs) do
    cast(sighting, attrs, @geolocation_fields)
  end

  @doc """
  Update point 2 — form submission.

  `attrs` carries the submitter's own form params, so only fields the
  submitter may set are cast here. `verified` is admin-only and is written
  through `McEmcomm.Sightings.verify/2`; `member_id`, `exercise_id` and
  `exercise_location_id` are resolved server-side in
  `McEmcomm.Sightings.submit/3` and put on the attrs there.
  """
  def submit_changeset(sighting, attrs) do
    sighting
    |> cast(attrs, [
      :call_sign,
      :note,
      :claimed_responsibility,
      :member_id,
      :submitted_at,
      :exercise_id,
      :exercise_location_id
    ])
    |> update_change(:call_sign, fn
      nil -> nil
      call_sign -> call_sign |> String.trim() |> String.upcase()
    end)
    |> foreign_key_constraint(:member_id)
    |> foreign_key_constraint(:exercise_id)
    |> foreign_key_constraint(:exercise_location_id)
  end

  @doc "Retention scrub: nulls raw identifying fields, keeps aggregate ones."
  def scrub_changeset(sighting) do
    change(sighting,
      remote_ip: nil,
      user_agent: nil,
      sec_ch_ua: nil,
      sec_ch_ua_platform: nil,
      sec_ch_ua_mobile: nil,
      accept_language: nil,
      referer: nil,
      point: nil,
      accuracy: nil,
      altitude: nil,
      heading: nil,
      speed: nil,
      scrubbed_at: DateTime.utc_now()
    )
  end
end
