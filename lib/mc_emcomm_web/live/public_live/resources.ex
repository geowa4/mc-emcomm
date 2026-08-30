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
       # A visitor who cannot download a members-only document is not shown
       # one either: the titles and filenames are themselves operational
       # detail, and the tier matrix (spec §3) puts gated documents out of
       # public reach entirely.
       documents: Content.list_documents(active_only: true, members_only_allowed: can_download?),
       can_download?: can_download?
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>Resources</.header>

      <p>
        Operational resources for Monroe County ARES/RACES members, particularly those serving
        in net control and emergency communication roles.
      </p>

      <h2 class="text-xl font-semibold mt-6">Operational Resources</h2>
      <p>
        Our operational resources are maintained in a shared Google Drive folder for easy
        access and collaboration:
      </p>
      <p>
        <a
          id="drive-folder-link"
          class="btn btn-primary"
          href="https://drive.google.com/drive/folders/1rn-REahGMMtXxvXvK9lOqRb0DIv3kko7?usp=drive_link"
          target="_blank"
          rel="noopener"
        >
          View documents on Google Drive
        </a>
      </p>
      <p>The folder contains essential documents and resources for our organization:</p>
      <ul class="list-disc list-inside space-y-1">
        <li>
          Net control operations: net control station scripts and procedures, standard forms
          for emergency communications, check-in sheets and logging templates, and ARRL
          radiogram forms
        </li>
        <li>
          Organizational documents: organizational structure and hierarchy, training
          requirements and procedures, code of conduct, and operating procedures and protocols
        </li>
        <li>Additional resources: training materials, guides, and reference documents</li>
      </ul>
      <p class="text-base-content/70">
        If you have trouble accessing the folder or need additional materials, please contact <a
          class="link"
          href="mailto:secretary@monroecountyemcomm.org"
        >secretary@monroecountyemcomm.org</a>.
      </p>

      <h2 class="text-xl font-semibold mt-6">Published Documents</h2>

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
            <button class="btn btn-sm btn-outline" phx-click="download" phx-value-id={doc.id}>
              Download
            </button>
          </div>
        </li>
      </ul>
      <p :if={@documents == []} class="text-base-content/70 mt-4">No resources published yet.</p>

      <p :if={!@can_download?} id="members-only-note" class="text-sm text-base-content/70 mt-4">
        Approved members have further operational resources.
        <.link navigate={~p"/users/log-in"} class="link">Log in</.link>
        to see them.
      </p>
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
