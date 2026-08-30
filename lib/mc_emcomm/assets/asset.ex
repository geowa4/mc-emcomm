defmodule McEmcomm.Assets.Asset do
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  schema "assets" do
    field :public_id, :string
    field :name, :string
    field :description, :string
    field :image_key, :string
    field :image_filename, :string
    field :image_content_type, :string
    field :active, :boolean, default: true

    timestamps(type: :utc_datetime)
  end

  def changeset(asset, attrs) do
    asset
    |> cast(attrs, [
      :public_id,
      :name,
      :description,
      :image_key,
      :image_filename,
      :image_content_type,
      :active
    ])
    |> validate_required([:public_id, :name])
    |> validate_format(:public_id, ~r/^[0-9A-HJKMNP-TV-Z]{6}$/,
      message: "must be 6 Crockford base32 characters"
    )
    |> unique_constraint(:public_id)
  end
end
