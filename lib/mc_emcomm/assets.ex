defmodule McEmcomm.Assets do
  @moduledoc "Inventory assets, identified by a short public QR-friendly id."

  import Ecto.Query, warn: false

  alias McEmcomm.Assets.Asset
  alias McEmcomm.Repo

  # Crockford base32 alphabet: excludes I, L, O, U to avoid visual confusion.
  @crockford_alphabet ~c"0123456789ABCDEFGHJKMNPQRSTVWXYZ"
  @public_id_length 6
  @max_generation_attempts 10

  def list_assets(opts \\ []) do
    Asset
    |> maybe_only_active(opts[:active_only])
    |> order_by([a], asc: a.name)
    |> Repo.all()
  end

  defp maybe_only_active(query, true), do: where(query, [a], a.active)
  defp maybe_only_active(query, _), do: query

  def get_asset!(id), do: Repo.get!(Asset, id)

  def get_asset_by_public_id(public_id) do
    Repo.get_by(Asset, public_id: String.upcase(public_id))
  end

  def change_asset(%Asset{} = asset, attrs \\ %{}) do
    Asset.changeset(asset, attrs)
  end

  @doc "Creates an asset, auto-generating a unique `public_id` unless one is given."
  def create_asset(attrs) do
    attrs = Map.new(attrs, fn {k, v} -> {to_string(k), v} end)

    attrs =
      if attrs["public_id"] in [nil, ""] do
        Map.put(attrs, "public_id", generate_unique_public_id())
      else
        attrs
      end

    %Asset{} |> Asset.changeset(attrs) |> Repo.insert()
  end

  def update_asset(%Asset{} = asset, attrs) do
    asset |> Asset.changeset(attrs) |> Repo.update()
  end

  def delete_asset(%Asset{} = asset), do: Repo.delete(asset)

  @doc "Generates a random 6-character Crockford base32 id, retrying on collision."
  def generate_unique_public_id(attempt \\ 0)

  def generate_unique_public_id(attempt) when attempt < @max_generation_attempts do
    candidate = generate_public_id()

    if Repo.exists?(from a in Asset, where: a.public_id == ^candidate) do
      generate_unique_public_id(attempt + 1)
    else
      candidate
    end
  end

  def generate_unique_public_id(_attempt) do
    raise "could not generate a unique asset public_id after #{@max_generation_attempts} attempts"
  end

  defp generate_public_id do
    1..@public_id_length
    |> Enum.map(fn _ -> Enum.random(@crockford_alphabet) end)
    |> to_string()
  end
end
