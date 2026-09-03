defmodule McEmcommWeb.AdminLive.PositionIndex do
  @moduledoc "Admin catalog of single-holder leadership positions."

  use McEmcommWeb, :live_view

  alias McEmcomm.Members
  alias McEmcomm.Members.Position
  alias McEmcommWeb.ParamHelpers

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: "Positions",
       positions: Members.list_positions(holders: :all),
       editing: nil,
       form: nil,
       holder_for: nil,
       holder_results: nil,
       holder_query: ""
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} active_net={@active_net}>
      <.header>
        Leadership positions
        <:actions>
          <.button phx-click="new" class="btn btn-primary">New position</.button>
        </:actions>
      </.header>

      <.modal
        :if={@form}
        id="position-modal"
        title={if @editing && @editing.id, do: "Edit position", else: "New position"}
        on_close="cancel"
      >
        <.form for={@form} id="position-form" phx-change="validate" phx-submit="save">
          <.input field={@form[:name]} label="Name" required />
          <.input field={@form[:sort_order]} type="number" label="Sort order" min="1" required />
          <.input
            field={@form[:grants_admin]}
            type="checkbox"
            label="Grants site admin to the holder"
          />
          <.input
            field={@form[:notify_on_new_member]}
            type="checkbox"
            label="Email the holder when a new member joins"
          />
          <div class="modal-action">
            <button type="button" phx-click="cancel" class="btn btn-ghost">Cancel</button>
            <.button class="btn btn-primary">Save</.button>
          </div>
        </.form>
      </.modal>

      <p id="positions-reorder-help" class="text-sm text-base-content/70">
        Drag a row, or use its move buttons, to change the order positions are listed in.
      </p>
      <div class="overflow-x-auto">
        <table class="table table-zebra" aria-describedby="positions-reorder-help">
          <thead>
            <tr>
              <th scope="col"><span class="sr-only">Reorder</span></th>
              <th scope="col">Sort</th>
              <th scope="col">Name</th>
              <th scope="col">Holder</th>
              <th scope="col"><span class="sr-only">Actions</span></th>
            </tr>
          </thead>
          <tbody id="positions-rows" phx-hook=".SortableRows">
            <tr
              :for={{p, index} <- Enum.with_index(@positions)}
              id={"position-row-#{p.id}"}
              data-id={p.id}
              draggable="true"
              class="cursor-grab"
            >
              <td class="whitespace-nowrap">
                <.icon name="hero-bars-3" class="size-4 text-base-content/40" />
                <button
                  id={"move-up-#{p.id}"}
                  type="button"
                  class="btn btn-ghost btn-xs"
                  phx-click="move"
                  phx-value-id={p.id}
                  phx-value-dir="up"
                  disabled={index == 0}
                  aria-label={"Move #{p.name} up"}
                >
                  <.icon name="hero-chevron-up" class="size-4" />
                </button>
                <button
                  id={"move-down-#{p.id}"}
                  type="button"
                  class="btn btn-ghost btn-xs"
                  phx-click="move"
                  phx-value-id={p.id}
                  phx-value-dir="down"
                  disabled={index == length(@positions) - 1}
                  aria-label={"Move #{p.name} down"}
                >
                  <.icon name="hero-chevron-down" class="size-4" />
                </button>
              </td>
              <td>{p.sort_order}</td>
              <td>
                {p.name}
                <span :if={p.grants_admin} class="badge badge-sm badge-primary">admin</span>
                <span :if={p.notify_on_new_member} class="badge badge-sm badge-secondary">
                  notifies
                </span>
              </td>
              <td>
                <button
                  type="button"
                  class="link link-hover"
                  id={"change-holder-#{p.id}"}
                  phx-click="change_holder"
                  phx-value-id={p.id}
                  aria-label={"Change holder of #{p.name}"}
                >
                  <span :if={p.members == []} class="text-base-content/70 italic">Vacant</span>
                  <span :for={member <- p.members}>
                    {member.name}
                    <span :if={member.status != :approved} class="badge badge-sm">
                      {member.status}
                    </span>
                  </span>
                </button>
              </td>
              <td class="w-0 font-semibold">
                <div class="flex gap-4">
                  <button
                    type="button"
                    class="link link-hover"
                    phx-click="edit"
                    phx-value-id={p.id}
                    aria-label={"Edit #{p.name}"}
                  >
                    Edit
                  </button>
                  <button
                    type="button"
                    class="link link-hover"
                    phx-click="delete"
                    phx-value-id={p.id}
                    data-confirm="Delete this position?"
                    aria-label={"Delete #{p.name}"}
                  >
                    Delete
                  </button>
                </div>
              </td>
            </tr>
          </tbody>
        </table>
      </div>

      <.modal
        :if={@holder_for}
        id="holder-modal"
        title={"Change holder — #{@holder_for.name}"}
        on_close="close_holder"
      >
        <p class="text-sm mb-4">
          Current holder:
          <span :if={@holder_for.members == []} class="text-base-content/70 italic">Vacant</span>
          <span :for={member <- @holder_for.members} class="font-semibold">
            {member.name}<span :if={member.call_sign}> &middot; {member.call_sign}</span>
          </span>
        </p>
        <form id="holder-search-form" phx-submit="search_members">
          <.input
            name="call_sign"
            value={@holder_query}
            label="Call sign"
            placeholder="Full or partial call sign, then Enter"
            phx-mounted={JS.focus()}
            autocomplete="off"
          />
        </form>
        <div id="holder-results-region" aria-live="polite">
          <ul
            :if={@holder_results}
            id="holder-results"
            class="menu bg-base-100 rounded-box border border-base-300 mt-2 w-full"
            aria-label="Matching members"
          >
            <li :if={@holder_results == []} class="menu-title">No members match that call sign.</li>
            <li :for={member <- @holder_results}>
              <button type="button" phx-click="assign_holder" phx-value-member-id={member.id}>
                <span class="font-mono">{member.call_sign}</span>
                {member.name}
              </button>
            </li>
          </ul>
        </div>
        <div class="modal-action">
          <button
            :if={@holder_for.members != []}
            type="button"
            phx-click="vacate_holder"
            class="btn btn-outline btn-warning"
          >
            Vacate
          </button>
          <button type="button" phx-click="close_holder" class="btn btn-ghost">Close</button>
        </div>
      </.modal>

      <script :type={Phoenix.LiveView.ColocatedHook} name=".SortableRows">
        export default {
          ids() {
            return Array.from(this.el.querySelectorAll("tr[data-id]")).map((row) => row.dataset.id)
          },
          mounted() {
            this.dragged = null
            this.el.addEventListener("dragstart", (e) => {
              const row = e.target.closest("tr[data-id]")
              if (!row) return
              this.dragged = row
              this.startOrder = this.ids().join()
              e.dataTransfer.effectAllowed = "move"
            })
            this.el.addEventListener("dragover", (e) => {
              if (!this.dragged) return
              e.preventDefault()
              const over = e.target.closest("tr[data-id]")
              if (!over || over === this.dragged) return
              const rows = Array.from(this.el.querySelectorAll("tr[data-id]"))
              if (rows.indexOf(this.dragged) < rows.indexOf(over)) {
                over.after(this.dragged)
              } else {
                over.before(this.dragged)
              }
            })
            this.el.addEventListener("drop", (e) => e.preventDefault())
            this.el.addEventListener("dragend", () => {
              if (!this.dragged) return
              this.dragged = null
              const ids = this.ids()
              if (ids.join() !== this.startOrder) this.pushEvent("reorder", {ids: ids})
            })
          },
        }
      </script>
    </Layouts.app>
    """
  end

  @impl true
  def handle_event("new", _params, socket) do
    position = %Position{sort_order: Members.next_position_sort_order()}

    {:noreply,
     assign(socket, editing: position, form: to_form(Members.change_position(position)))}
  end

  def handle_event("edit", %{"id" => id}, socket) do
    position = Members.get_position!(id)

    {:noreply,
     assign(socket, editing: position, form: to_form(Members.change_position(position)))}
  end

  def handle_event("cancel", _params, socket),
    do: {:noreply, assign(socket, editing: nil, form: nil)}

  def handle_event("validate", %{"position" => params}, socket) do
    form =
      socket.assigns.editing
      |> Members.change_position(params)
      |> Map.put(:action, :validate)
      |> to_form()

    {:noreply, assign(socket, form: form)}
  end

  def handle_event("save", %{"position" => params}, socket) do
    result =
      case socket.assigns.editing do
        %Position{id: nil} -> Members.create_position(params)
        position -> Members.update_position(position, params)
      end

    case result do
      {:ok, _} ->
        {:noreply,
         assign(socket, editing: nil, form: nil, positions: Members.list_positions(holders: :all))}

      {:error, changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  def handle_event("change_holder", %{"id" => id}, socket) do
    position = Enum.find(socket.assigns.positions, &(&1.id == ParamHelpers.id(id)))
    {:noreply, assign(socket, holder_for: position, holder_results: nil, holder_query: "")}
  end

  def handle_event("search_members", %{"call_sign" => query}, socket) do
    {:noreply,
     assign(socket,
       holder_results: Members.search_members_by_call_sign(query),
       holder_query: query
     )}
  end

  def handle_event("assign_holder", %{"member-id" => member_id}, socket) do
    member = Members.get_member!(member_id)

    socket =
      case Members.assign_position(member, socket.assigns.holder_for) do
        {:ok, _} ->
          socket

        {:error, :not_approved} ->
          put_flash(socket, :error, "Only approved members can hold positions.")
      end

    {:noreply,
     assign(socket,
       holder_for: nil,
       holder_results: nil,
       positions: Members.list_positions(holders: :all)
     )}
  end

  def handle_event("vacate_holder", _params, socket) do
    :ok = Members.vacate_position(socket.assigns.holder_for)

    {:noreply,
     assign(socket,
       holder_for: nil,
       holder_results: nil,
       positions: Members.list_positions(holders: :all)
     )}
  end

  def handle_event("close_holder", _params, socket),
    do: {:noreply, assign(socket, holder_for: nil, holder_results: nil)}

  def handle_event("reorder", %{"ids" => ids}, socket) do
    ids |> Enum.map(&ParamHelpers.id/1) |> Enum.reject(&is_nil/1) |> reorder(socket)
  end

  # Keyboard alternative to dragging: swap the row with its neighbour.
  def handle_event("move", %{"id" => id, "dir" => dir}, socket) when dir in ~w(up down) do
    ids = Enum.map(socket.assigns.positions, & &1.id)
    id = ParamHelpers.id(id)
    index = Enum.find_index(ids, &(&1 == id))
    target = if dir == "up", do: index && index - 1, else: index && index + 1

    if index && target >= 0 && target < length(ids) do
      ids |> List.delete_at(index) |> List.insert_at(target, id) |> reorder(socket)
    else
      {:noreply, socket}
    end
  end

  def handle_event("delete", %{"id" => id}, socket) do
    case Members.get_position!(id) |> Members.delete_position() do
      {:ok, _} ->
        {:noreply, assign(socket, positions: Members.list_positions(holders: :all))}

      {:error, :position_held} ->
        {:noreply,
         put_flash(socket, :error, "A member holds that position. Remove it from them first.")}
    end
  end

  defp reorder(ids, socket) do
    case Members.reorder_positions(ids) do
      :ok ->
        {:noreply, assign(socket, positions: Members.list_positions(holders: :all))}

      {:error, :stale} ->
        {:noreply,
         socket
         |> put_flash(:error, "The list changed underneath you — showing the latest order.")
         |> assign(positions: Members.list_positions(holders: :all))}
    end
  end
end
