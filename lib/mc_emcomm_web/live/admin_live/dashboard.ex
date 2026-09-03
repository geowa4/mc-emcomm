defmodule McEmcommWeb.AdminLive.Dashboard do
  use McEmcommWeb, :live_view

  alias McEmcomm.Members

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket, page_title: "Admin", pending_count: length(Members.list_pending_members()))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} active_net={@active_net}>
      <.header>Admin</.header>

      <div class="grid gap-4 sm:grid-cols-3 mt-4">
        <.link navigate={~p"/admin/members"} class="card bg-base-100 shadow-sm border border-base-300">
          <div class="card-body">
            <h2 class="card-title">
              Members
              <span :if={@pending_count > 0} class="badge badge-warning">{@pending_count} pending</span>
            </h2>
            <p>Approvals, roles, and audit trail.</p>
          </div>
        </.link>
        <.link
          navigate={~p"/admin/positions"}
          class="card bg-base-100 shadow-sm border border-base-300"
        >
          <div class="card-body">
            <h2 class="card-title">Leadership positions</h2>
            <p>The catalog of single-holder positions.</p>
          </div>
        </.link>
        <.link
          navigate={~p"/admin/operations"}
          class="card bg-base-100 shadow-sm border border-base-300"
        >
          <div class="card-body">
            <h2 class="card-title">Operations</h2>
          </div>
        </.link>
        <.link
          navigate={~p"/admin/inventory"}
          class="card bg-base-100 shadow-sm border border-base-300"
        >
          <div class="card-body">
            <h2 class="card-title">Inventory &amp; QR codes</h2>
          </div>
        </.link>
        <.link
          navigate={~p"/admin/capabilities"}
          class="card bg-base-100 shadow-sm border border-base-300"
        >
          <div class="card-body">
            <h2 class="card-title">Capabilities catalog</h2>
          </div>
        </.link>
        <.link
          navigate={~p"/admin/locations"}
          class="card bg-base-100 shadow-sm border border-base-300"
        >
          <div class="card-body">
            <h2 class="card-title">Default locations</h2>
            <p>Named map points selectable at net check-in.</p>
          </div>
        </.link>
        <.link navigate={~p"/admin/courses"} class="card bg-base-100 shadow-sm border border-base-300">
          <div class="card-body">
            <h2 class="card-title">Courses catalog</h2>
          </div>
        </.link>
        <.link
          navigate={~p"/admin/certifications"}
          class="card bg-base-100 shadow-sm border border-base-300"
        >
          <div class="card-body">
            <h2 class="card-title">Certifications catalog</h2>
          </div>
        </.link>
        <.link
          navigate={~p"/admin/documents"}
          class="card bg-base-100 shadow-sm border border-base-300"
        >
          <div class="card-body">
            <h2 class="card-title">Documents</h2>
          </div>
        </.link>
      </div>
    </Layouts.app>
    """
  end
end
