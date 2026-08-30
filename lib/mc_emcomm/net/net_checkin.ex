defmodule McEmcomm.Net.NetCheckin do
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @quadrants ~w(NE NW SE SW out_of_county)a

  schema "net_checkins" do
    field :call_sign, :string
    field :quadrant, Ecto.Enum, values: @quadrants
    field :notes, :string
    field :recorded_at, :utc_datetime_usec

    belongs_to :net_session, McEmcomm.Net.NetSession
    belongs_to :member, McEmcomm.Members.Member

    timestamps(type: :utc_datetime)
  end

  def changeset(checkin, attrs) do
    checkin
    |> cast(attrs, [:net_session_id, :call_sign, :member_id, :quadrant, :notes, :recorded_at])
    |> validate_required([:net_session_id, :call_sign, :recorded_at])
    |> update_change(:call_sign, &String.upcase(String.trim(&1)))
    |> foreign_key_constraint(:net_session_id)
    |> foreign_key_constraint(:member_id)
  end
end
