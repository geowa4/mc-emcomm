defmodule McEmcomm.Content do
  @moduledoc "Public content: Resources documents. Static pages (Home, About, Training,
  Calendar, Donations) render fixed copy plus leadership from `McEmcomm.Members`."

  import Ecto.Query, warn: false

  alias McEmcomm.Content.Document
  alias McEmcomm.Repo

  def list_documents(opts \\ []) do
    Document
    |> maybe_only_active(opts[:active_only])
    |> maybe_exclude_members_only(opts[:members_only_allowed])
    |> order_by([d], asc: d.position, asc: d.title)
    |> Repo.all()
  end

  defp maybe_only_active(query, true), do: where(query, [d], d.active)
  defp maybe_only_active(query, _), do: query

  defp maybe_exclude_members_only(query, true), do: query
  defp maybe_exclude_members_only(query, _), do: where(query, [d], not d.members_only)

  def get_document!(id), do: Repo.get!(Document, id)

  def change_document(%Document{} = document, attrs \\ %{}) do
    Document.changeset(document, attrs)
  end

  def create_document(attrs), do: %Document{} |> Document.changeset(attrs) |> Repo.insert()

  def update_document(%Document{} = document, attrs) do
    document |> Document.changeset(attrs) |> Repo.update()
  end

  def delete_document(%Document{} = document), do: Repo.delete(document)
end
