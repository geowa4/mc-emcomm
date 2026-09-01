defmodule McEmcommWeb.OperationLive.Index do
  use McEmcommWeb, :live_view

  alias McEmcomm.Operations

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: "Operations", operations: Operations.list_operations())}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>Operations</.header>

      <ul :if={@operations != []} class="list bg-base-100 rounded-box border border-base-300 mt-4">
        <li :for={operation <- @operations} class="list-row">
          <div>
            <.link
              navigate={~p"/app/operations/#{operation.id}"}
              class="font-semibold link link-hover"
            >
              {operation.title}
            </.link>
            <div class="text-sm text-base-content/70">
              {Calendar.strftime(operation.starts_at, "%B %d, %Y %I:%M %p")}
              <span class="badge badge-sm badge-ghost ml-2">{operation.visibility}</span>
            </div>
          </div>
        </li>
      </ul>
      <p :if={@operations == []} class="text-base-content/70 mt-4">No operations yet.</p>
    </Layouts.app>
    """
  end
end
