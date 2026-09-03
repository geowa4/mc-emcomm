defmodule McEmcommWeb.AdminLive.DocumentIndex do
  use McEmcommWeb, :live_view

  alias McEmcomm.Content
  alias McEmcomm.Content.Document
  alias McEmcomm.Storage

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(
       page_title: "Documents",
       documents: Content.list_documents(members_only_allowed: true),
       form: to_form(Content.change_document(%Document{}))
     )
     |> allow_upload(:file, accept: :any, max_entries: 1, external: &presign_entry/2)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} active_net={@active_net}>
      <.header>Documents</.header>

      <form id="document-form" phx-change="validate" phx-submit="save" class="max-w-md mb-6">
        <.input name="title" label="Title" value="" required />
        <.live_file_input upload={@uploads.file} />
        <label class="label mt-2">
          <input
            type="checkbox"
            name="members_only"
            value="true"
            class="checkbox checkbox-sm"
            checked
          /> Members only
        </label>
        <.button class="btn btn-primary mt-2">Upload document</.button>
      </form>

      <.table id="documents" rows={@documents}>
        <:col :let={d} label="Title">{d.title}</:col>
        <:col :let={d} label="Filename">{d.filename}</:col>
        <:col :let={d} label="Members only">{d.members_only}</:col>
        <:col :let={d} label="Active">{d.active}</:col>
        <:action :let={d}>
          <.link phx-click="toggle_active" phx-value-id={d.id}>
            {if d.active, do: "Deactivate", else: "Activate"}
          </.link>
        </:action>
        <:action :let={d}>
          <.link phx-click="delete" phx-value-id={d.id} data-confirm="Delete this document?">Delete</.link>
        </:action>
      </.table>
    </Layouts.app>
    """
  end

  @impl true
  def handle_event("validate", _params, socket), do: {:noreply, socket}

  def handle_event("save", params, socket) do
    uploaded =
      consume_uploaded_entries(socket, :file, fn %{key: key}, entry ->
        {:ok, %{key: key, filename: entry.client_name, content_type: entry.client_type}}
      end)

    case uploaded do
      [%{key: key, filename: filename, content_type: content_type}] ->
        attrs = %{
          title: params["title"],
          key: key,
          filename: filename,
          content_type: content_type,
          members_only: params["members_only"] == "true"
        }

        case Content.create_document(attrs) do
          {:ok, _} ->
            {:noreply,
             assign(socket,
               documents: Content.list_documents(members_only_allowed: true),
               form: to_form(Content.change_document(%Document{}))
             )}

          {:error, changeset} ->
            {:noreply, assign(socket, form: to_form(changeset))}
        end

      [] ->
        {:noreply, put_flash(socket, :error, "Choose a file first.")}
    end
  end

  def handle_event("toggle_active", %{"id" => id}, socket) do
    document = Content.get_document!(id)
    Content.update_document(document, %{active: !document.active})
    {:noreply, assign(socket, documents: Content.list_documents(members_only_allowed: true))}
  end

  def handle_event("delete", %{"id" => id}, socket) do
    Content.get_document!(id) |> Content.delete_document()
    {:noreply, assign(socket, documents: Content.list_documents(members_only_allowed: true))}
  end

  defp presign_entry(entry, socket) do
    key = Storage.build_key("documents", entry.client_name)
    presigned = Storage.presign_upload(key, entry.client_type)
    meta = %{uploader: "S3", key: key, url: presigned.url, fields: presigned.fields}
    {:ok, meta, socket}
  end
end
