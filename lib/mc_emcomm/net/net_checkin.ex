defmodule McEmcomm.Net.NetCheckin do
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  schema "net_checkins" do
    field :call_sign, :string
    # "K4GWA-4": set only from APRS position reports, never cast.
    field :aprs_call_sign, :string
    field :location_name, :string
    field :location_point, Geo.PostGIS.Geometry
    field :notes, :string
    field :recorded_at, :utc_datetime_usec
    field :ended_at, :utc_datetime_usec

    belongs_to :net_session, McEmcomm.Net.NetSession
    belongs_to :member, McEmcomm.Members.Member

    timestamps(type: :utc_datetime)
  end

  def changeset(checkin, attrs) do
    checkin
    |> cast(attrs, [
      :net_session_id,
      :call_sign,
      :member_id,
      :location_name,
      :location_point,
      :notes,
      :recorded_at
    ])
    |> validate_required([:net_session_id, :call_sign, :recorded_at])
    |> update_change(:call_sign, &String.upcase(String.trim(&1)))
    |> foreign_key_constraint(:net_session_id)
    |> foreign_key_constraint(:member_id)
  end

  @doc """
  Corrections after entry; `member_id` is re-matched and the location snapshot
  is resolved programmatically in the context, never cast.
  """
  def update_changeset(checkin, attrs) do
    checkin
    |> cast(attrs, [:call_sign, :notes])
    |> validate_required([:call_sign])
    |> update_change(:call_sign, &String.upcase(String.trim(&1)))
    |> foreign_key_constraint(:member_id)
  end

  def end_changeset(checkin, ended_at) do
    change(checkin, ended_at: ended_at)
  end

  @doc """
  Moves the check-in to a position received over APRS-IS from `station`
  (the full call sign with SSID), marking it APRS-tracked.
  """
  def aprs_position_changeset(checkin, station, %Geo.Point{} = point) do
    change(checkin, aprs_call_sign: station, location_name: "APRS", location_point: point)
  end

  @doc "Seconds on the net, or `nil` while the check-in is still active."
  def duration_seconds(%__MODULE__{ended_at: nil}), do: nil

  def duration_seconds(%__MODULE__{recorded_at: recorded_at, ended_at: ended_at}) do
    DateTime.diff(ended_at, recorded_at, :second)
  end
end
