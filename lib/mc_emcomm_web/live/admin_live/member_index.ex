defmodule McEmcommWeb.AdminLive.MemberIndex do
  @moduledoc "Membership approvals, position editing, and the membership_audit trail (§9 Admin approval)."

  use McEmcommWeb, :live_view

  alias McEmcomm.Members
  alias McEmcommWeb.ParamHelpers

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: "Members",
       members: Members.list_members(),
       positions: Members.list_positions(),
       reason_for: nil,
       audit_for: nil
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>Members</.header>

      <.table id="members" rows={@members}>
        <:col :let={m} label="Name">{m.name}</:col>
        <:col :let={m} label="Call sign">{m.call_sign}</:col>
        <:col :let={m} label="Status"><span class="badge badge-sm">{m.status}</span></:col>
        <:col :let={m} label="Positions">
          <form id={"positions-form-#{m.id}"} phx-change="update_positions" phx-value-id={m.id}>
            <input type="hidden" name="position_ids[]" value="" />
            <button
              type="button"
              class="btn btn-sm btn-outline max-w-56 justify-between gap-2 font-normal"
              popovertarget={"positions-popover-#{m.id}"}
              style={"anchor-name:--positions-anchor-#{m.id}"}
            >
              <span class="truncate">{position_summary(m)}</span>
              <.icon name="hero-chevron-down" class="size-4 shrink-0" />
            </button>
            <div
              id={"positions-popover-#{m.id}"}
              popover
              class="dropdown w-64 rounded-box border border-base-300 bg-base-100 p-2 shadow-md"
              style={"position-anchor:--positions-anchor-#{m.id}"}
            >
              <label
                :for={position <- @positions}
                class="label flex cursor-pointer justify-start gap-2 py-1 text-sm"
              >
                <input
                  type="checkbox"
                  name="position_ids[]"
                  value={position.id}
                  checked={position.id in Enum.map(m.positions, & &1.id)}
                  disabled={
                    m.status != :approved and position.id not in Enum.map(m.positions, & &1.id)
                  }
                  class="checkbox checkbox-xs"
                />
                {position.name}
              </label>
            </div>
          </form>
        </:col>
        <:action :let={m}>
          <.link :if={m.status == :pending} phx-click="approve" phx-value-id={m.id}>Approve</.link>
        </:action>
        <:action :let={m}>
          <.link
            :if={m.status == :pending}
            phx-click="show_reason"
            phx-value-id={m.id}
            phx-value-to="rejected"
          >
            Reject
          </.link>
          <.link
            :if={m.status == :approved}
            phx-click="show_reason"
            phx-value-id={m.id}
            phx-value-to="inactive"
          >
            Deactivate
          </.link>
          <.link :if={m.status == :inactive} phx-click="approve" phx-value-id={m.id}>Reactivate</.link>
          <.link :if={m.status == :rejected} phx-click="reopen" phx-value-id={m.id}>Reopen</.link>
        </:action>
        <:action :let={m}>
          <.link phx-click="show_audit" phx-value-id={m.id}>Audit</.link>
        </:action>
      </.table>

      <dialog
        :if={@reason_for}
        id="reason-modal"
        class="modal modal-open"
        phx-window-keydown="cancel_reason"
        phx-key="escape"
      >
        <div class="modal-box">
          <h3 class="text-lg font-semibold mb-2">
            {if @reason_for.to == "inactive", do: "Deactivate member", else: "Reject member"}
          </h3>
          <.form
            for={to_form(%{"reason" => ""}, as: "transition")}
            id="reason-form"
            phx-submit="do_transition"
          >
            <input type="hidden" name="transition[id]" value={@reason_for.id} />
            <input type="hidden" name="transition[to]" value={@reason_for.to} />
            <.input
              name="transition[reason]"
              value=""
              label={"Reason for #{@reason_for.to}"}
              required
            />
            <div class="modal-action">
              <button type="button" phx-click="cancel_reason" class="btn btn-ghost">Cancel</button>
              <.button class="btn btn-primary">Confirm</.button>
            </div>
          </.form>
        </div>
        <button type="button" class="modal-backdrop" phx-click="cancel_reason" aria-label="Close"></button>
      </dialog>

      <dialog
        :if={@audit_for}
        id="audit-modal"
        class="modal modal-open"
        phx-window-keydown="close_audit"
        phx-key="escape"
      >
        <div class="modal-box">
          <h3 class="text-lg font-semibold mb-2">Audit trail &mdash; {@audit_for.call_sign}</h3>
          <ul class="list bg-base-100 rounded-box border border-base-300">
            <li :for={a <- Members.list_audit_for_member(@audit_for.id)} class="list-row">
              {a.from_status} &rarr; {a.to_status} &middot; {a.inserted_at}
              <span :if={a.reason}> &mdash; {a.reason}</span>
            </li>
          </ul>
          <div class="modal-action">
            <button type="button" phx-click="close_audit" class="btn btn-ghost">Close</button>
          </div>
        </div>
        <button type="button" class="modal-backdrop" phx-click="close_audit" aria-label="Close"></button>
      </dialog>
    </Layouts.app>
    """
  end

  @impl true
  def handle_event("approve", %{"id" => id}, socket) do
    member = Members.get_member!(id)
    to_status = if member.status == :inactive, do: :approved, else: :approved
    transition(socket, member, to_status, nil)
  end

  def handle_event("reopen", %{"id" => id}, socket) do
    transition(socket, Members.get_member!(id), :pending, nil)
  end

  def handle_event("show_reason", %{"id" => id, "to" => to}, socket) do
    {:noreply, assign(socket, reason_for: %{id: id, to: to})}
  end

  def handle_event("cancel_reason", _params, socket),
    do: {:noreply, assign(socket, reason_for: nil)}

  def handle_event(
        "do_transition",
        %{"transition" => %{"id" => id, "to" => to, "reason" => reason}},
        socket
      ) do
    socket = assign(socket, reason_for: nil)
    # `to` stays a string: Members.transition_status/4 validates it against the
    # legal transitions before it ever becomes an atom.
    transition(socket, Members.get_member!(id), to, reason)
  end

  def handle_event("show_audit", %{"id" => id}, socket) do
    {:noreply, assign(socket, audit_for: Members.get_member!(id))}
  end

  def handle_event("close_audit", _params, socket),
    do: {:noreply, assign(socket, audit_for: nil)}

  def handle_event("update_positions", %{"id" => id} = params, socket) do
    position_ids =
      params
      |> Map.get("position_ids", [])
      |> Enum.map(&ParamHelpers.id/1)
      |> Enum.reject(&is_nil/1)

    member = Members.get_member!(id)

    case Members.update_member_positions(member, position_ids) do
      {:ok, _} ->
        {:noreply, assign(socket, members: Members.list_members())}

      {:error, :not_approved} ->
        {:noreply,
         socket
         |> put_flash(:error, "Only approved members can hold positions.")
         |> assign(members: Members.list_members())}
    end
  end

  defp position_summary(%{positions: []}), do: "None"
  defp position_summary(%{positions: positions}), do: Enum.map_join(positions, ", ", & &1.name)

  defp transition(socket, member, to_status, reason) do
    actor = socket.assigns.current_scope.user

    case Members.transition_status(member, to_status, actor, reason) do
      {:ok, _} ->
        {:noreply, assign(socket, members: Members.list_members())}

      {:error, :illegal_transition} ->
        {:noreply, put_flash(socket, :error, "That status change isn't allowed.")}

      {:error, changeset} ->
        {:noreply, put_flash(socket, :error, "Error: #{inspect(changeset.errors)}")}
    end
  end
end
