defmodule McEmcommWeb.AppLive.Dashboard do
  use McEmcommWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: "Member Portal")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} active_net={@active_net}>
      <.header>Member Portal</.header>

      <div class="grid gap-4 sm:grid-cols-2 mt-4">
        <.link navigate={~p"/app/profile"} class="card bg-base-100 shadow-sm border border-base-300">
          <div class="card-body">
            <h2 class="card-title">My Profile</h2>
            <p>QTH, capabilities, courses, and certifications.</p>
          </div>
        </.link>
        <.link
          navigate={~p"/app/operations"}
          class="card bg-base-100 shadow-sm border border-base-300"
        >
          <div class="card-body">
            <h2 class="card-title">Operations</h2>
            <p>Locations, attachments, and attendance.</p>
          </div>
        </.link>
        <.link navigate={~p"/app/inventory"} class="card bg-base-100 shadow-sm border border-base-300">
          <div class="card-body">
            <h2 class="card-title">Inventory</h2>
            <p>Asset sighting logs and details.</p>
          </div>
        </.link>
        <.link navigate={~p"/app/net"} class="card bg-base-100 shadow-sm border border-base-300">
          <div class="card-body">
            <h2 class="card-title">Net Console</h2>
            <p>Start a net and take live check-ins.</p>
          </div>
        </.link>
      </div>
    </Layouts.app>
    """
  end
end
