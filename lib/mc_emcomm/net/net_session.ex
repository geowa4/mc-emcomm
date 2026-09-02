defmodule McEmcomm.Net.NetSession do
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  schema "net_sessions" do
    field :name, :string
    field :aprs_keyword, :string
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
    |> cast(attrs, [
      :started_by_member_id,
      :operation_id,
      :name,
      :aprs_keyword,
      :started_at,
      :ended_at,
      :notes
    ])
    |> validate_required([:started_by_member_id, :name, :aprs_keyword, :started_at])
    |> validate_aprs_keyword()
    |> foreign_key_constraint(:started_by_member_id)
    |> foreign_key_constraint(:operation_id)
  end

  @doc """
  Changes only the APRS keyword. The keyword is matched as a case-insensitive
  substring of a position report's comment, so it must be a single word; the
  partial unique index keeps it unique among active nets.
  """
  def aprs_keyword_changeset(net_session, keyword) do
    net_session
    |> cast(%{"aprs_keyword" => keyword}, [:aprs_keyword])
    |> validate_required([:aprs_keyword])
    |> validate_aprs_keyword()
  end

  defp validate_aprs_keyword(changeset) do
    changeset
    |> update_change(:aprs_keyword, &String.trim/1)
    |> validate_length(:aprs_keyword, min: 2, max: 32)
    |> validate_format(:aprs_keyword, ~r/^\S+$/, message: "can't contain spaces")
    |> unique_constraint(:aprs_keyword,
      name: :net_sessions_active_aprs_keyword_index,
      message: "is already used by an active net"
    )
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
