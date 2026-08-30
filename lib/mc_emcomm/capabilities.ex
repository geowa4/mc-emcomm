defmodule McEmcomm.Capabilities do
  @moduledoc "Admin catalog of capabilities and each member's recorded capabilities."

  import Ecto.Query, warn: false

  alias McEmcomm.Capabilities.Capability
  alias McEmcomm.Capabilities.MemberCapability
  alias McEmcomm.Repo

  def list_capabilities(opts \\ []) do
    Capability
    |> maybe_only_active(opts[:active_only])
    |> order_by([c], asc: c.name)
    |> Repo.all()
  end

  defp maybe_only_active(query, true), do: where(query, [c], c.active)
  defp maybe_only_active(query, _), do: query

  def get_capability!(id), do: Repo.get!(Capability, id)

  def change_capability(%Capability{} = capability, attrs \\ %{}) do
    Capability.changeset(capability, attrs)
  end

  def create_capability(attrs) do
    %Capability{} |> Capability.changeset(attrs) |> Repo.insert()
  end

  def update_capability(%Capability{} = capability, attrs) do
    capability |> Capability.changeset(attrs) |> Repo.update()
  end

  def delete_capability(%Capability{} = capability), do: Repo.delete(capability)

  def list_member_capabilities(member_id) do
    MemberCapability
    |> where([mc], mc.member_id == ^member_id)
    |> preload(:capability)
    |> Repo.all()
  end

  def change_member_capability(%MemberCapability{} = mc, attrs \\ %{}) do
    MemberCapability.changeset(mc, attrs)
  end

  def add_member_capability(attrs) do
    %MemberCapability{} |> MemberCapability.changeset(attrs) |> Repo.insert()
  end

  def remove_member_capability(%MemberCapability{} = mc), do: Repo.delete(mc)
end
