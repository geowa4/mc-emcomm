defmodule McEmcomm.Content.Document do
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  schema "documents" do
    field :title, :string
    field :key, :string
    field :filename, :string
    field :content_type, :string
    field :members_only, :boolean, default: true
    field :active, :boolean, default: true
    field :position, :integer, default: 0

    timestamps(type: :utc_datetime)
  end

  def changeset(document, attrs) do
    document
    |> cast(attrs, [:title, :key, :filename, :content_type, :members_only, :active, :position])
    |> validate_required([:title, :key, :filename, :content_type])
  end
end
