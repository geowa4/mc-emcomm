defmodule McEmcomm.Net.NetSession do
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  schema "net_sessions" do
    field :name, :string
    field :started_at, :utc_datetime
    field :ended_at, :utc_datetime
    field :notes, :string

    belongs_to :started_by_member, McEmcomm.Members.Member

    has_many :checkins, McEmcomm.Net.NetCheckin

    timestamps(type: :utc_datetime)
  end

  def changeset(net_session, attrs) do
    net_session
    |> cast(attrs, [:started_by_member_id, :name, :started_at, :ended_at, :notes])
    |> validate_required([:started_by_member_id, :started_at])
    |> foreign_key_constraint(:started_by_member_id)
  end

  def end_changeset(net_session, ended_at \\ DateTime.utc_now()) do
    change(net_session, ended_at: ended_at)
  end
end
