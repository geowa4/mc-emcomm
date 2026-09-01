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
    belongs_to :net_control_member, McEmcomm.Members.Member
    belongs_to :operation, McEmcomm.Operations.Operation

    has_many :checkins, McEmcomm.Net.NetCheckin

    timestamps(type: :utc_datetime)
  end

  def changeset(net_session, attrs) do
    net_session
    |> cast(attrs, [:started_by_member_id, :operation_id, :name, :started_at, :ended_at, :notes])
    |> validate_required([:started_by_member_id, :name, :started_at])
    |> foreign_key_constraint(:started_by_member_id)
    |> foreign_key_constraint(:operation_id)
  end

  @doc "Sets or vacates the net control operator; the id is never cast from user input."
  def net_control_changeset(net_session, member_id_or_nil) do
    net_session
    |> change(net_control_member_id: member_id_or_nil)
    |> foreign_key_constraint(:net_control_member_id)
  end

  @doc "Assigns the session to an operation, or clears the assignment with `nil`."
  def operation_changeset(net_session, operation_id_or_nil) do
    net_session
    |> change(operation_id: operation_id_or_nil)
    |> foreign_key_constraint(:operation_id)
  end

  def end_changeset(net_session, ended_at \\ DateTime.utc_now()) do
    change(net_session, ended_at: DateTime.truncate(ended_at, :second))
  end
end
