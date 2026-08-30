defmodule McEmcommWeb.PublicLive.Resources do
  use McEmcommWeb, :live_view

  alias McEmcomm.Accounts.Scope
  alias McEmcomm.Content
  alias McEmcomm.Storage

  @impl true
  def mount(_params, _session, socket) do
    can_download? =
      Scope.approved_member?(socket.assigns.current_scope) or
        Scope.admin?(socket.assigns.current_scope)

    {:ok,
     assign(socket,
       page_title: "Resources",
       documents: Content.list_documents(active_only: true),
       can_download?: can_download?
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>Resources</.header>

      <p>
        Operational resources for Monroe County EmComm members, particularly those serving in
        net control and emergency communication roles.
      </p>

      <ul :if={@documents != []} class="list bg-base-100 rounded-box border border-base-300 mt-4">
        <li :for={doc <- @documents} class="list-row items-center">
          <div class="flex-1">
            <div class="font-semibold">{doc.title}</div>
            <div class="text-sm text-base-content/70">
              {doc.filename}
              <span :if={doc.members_only} class="badge badge-sm badge-ghost ml-2">Members only</span>
            </div>
          </div>
          <div>
            <button
              :if={@can_download? or not doc.members_only}
              class="btn btn-sm btn-outline"
              phx-click="download"
              phx-value-id={doc.id}
            >
              Download
            </button>
            <span :if={!@can_download? and doc.members_only} class="text-sm text-base-content/50">
              <.link navigate={~p"/users/log-in"} class="link">Log in</.link> to download
            </span>
          </div>
        </li>
      </ul>
      <p :if={@documents == []} class="text-base-content/70 mt-4">No resources published yet.</p>
    </Layouts.app>
    """
  end

  @impl true
  def handle_event("download", %{"id" => id}, socket) do
    document = Content.get_document!(id)

    if document.members_only and not socket.assigns.can_download? do
      {:noreply, put_flash(socket, :error, "Log in as an approved member to download this file.")}
    else
      url = Storage.presign_download_url(document.key)
      {:noreply, redirect(socket, external: url)}
    end
  end
end
