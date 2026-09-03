defmodule McEmcommWeb.OperationLive.PublicIndex do
  use McEmcommWeb, :live_view

  alias McEmcomm.Operations

  @impl true
  def mount(_params, _session, socket) do
    operations = Operations.list_operations(visibility: :public)
    {:ok, assign(socket, page_title: "Public Operations", operations: operations)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} active_net={@active_net}>
      <.header>Public Operations</.header>

      <ul :if={@operations != []} class="list bg-base-100 rounded-box border border-base-300 mt-4">
        <li :for={operation <- @operations} class="list-row">
          <div>
            <.link navigate={~p"/operations/#{operation.id}"} class="font-semibold link link-hover">
              {operation.title}
            </.link>
            <div class="text-sm text-base-content/70">
              {Calendar.strftime(operation.starts_at, "%B %d, %Y %I:%M %p")}
            </div>
          </div>
        </li>
      </ul>
      <p :if={@operations == []} class="text-base-content/70 mt-4">No upcoming public operations.</p>

      <.link id="member-operations-link" navigate={~p"/app/operations"} class="btn btn-primary mt-4">
        View all operations in the member portal
      </.link>
    </Layouts.app>
    """
  end
end
