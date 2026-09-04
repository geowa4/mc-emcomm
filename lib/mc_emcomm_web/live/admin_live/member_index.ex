defmodule McEmcommWeb.AdminLive.MemberIndex do
  @moduledoc "Membership approvals, position editing, and the membership_audit trail (§9 Admin approval)."

  use McEmcommWeb, :live_view

  alias McEmcomm.Members
  alias McEmcommWeb.ParamHelpers

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(
       page_title: "Members",
       positions: Members.list_positions(),
       reason_for: nil,
       audit_for: nil
     )
     |> load_members()}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} active_net={@active_net}>
      <.header>Members</.header>

      <section id="pending-members-section" class="mb-10">
        <h2 class="flex items-center gap-2 text-lg font-semibold">
          Pending approval
          <span :if={@pending_members != []} class="badge badge-warning badge-sm">
            {length(@pending_members)}
          </span>
        </h2>
        <p
          :if={@pending_members == []}
          id="pending-members-empty"
          class="text-sm text-base-content/60"
        >
          No members are waiting for approval.
        </p>
        <.table
          :if={@pending_members != []}
          id="pending-members"
          rows={@pending_members}
          row_id={&"pending-members-#{&1.id}"}
        >
          <:col :let={m} label="Name">{m.name}</:col>
          <:col :let={m} label="Call sign">{m.call_sign}</:col>
          <:col :let={m} label="Registered">{Calendar.strftime(m.inserted_at, "%Y-%m-%d")}</:col>
          <:action :let={m}>
            <button type="button" class="link link-hover" phx-click="approve" phx-value-id={m.id}>Approve</button>
          </:action>
          <:action :let={m}>
            <button
              type="button"
              class="link link-hover"
              phx-click="show_reason"
              phx-value-id={m.id}
              phx-value-to="rejected"
            >Reject</button>
          </:action>
          <:action :let={m}>
            <button type="button" class="link link-hover" phx-click="show_audit" phx-value-id={m.id}>Audit</button>
          </:action>
        </.table>
      </section>

      <h2 class="text-lg font-semibold">All members</h2>
      <.table id="members" rows={@members} row_id={&"members-#{&1.id}"}>
        <:col :let={m} label="Name">{m.name}</:col>
        <:col :let={m} label="Call sign">{m.call_sign}</:col>
        <:col :let={m} label="Status"><span class="badge badge-sm">{m.status}</span></:col>
        <:col :let={m} label="Emergency contact">
          <span :if={m.emergency_contact_name} id={"emergency-contact-#{m.id}"} class="text-sm">
            {m.emergency_contact_name}
            <span :if={m.emergency_contact_relation}>({m.emergency_contact_relation})</span>
            <br />
            <a href={"tel:#{m.emergency_contact_phone}"} class="link link-hover">
              {m.emergency_contact_phone}
            </a>
          </span>
        </:col>
        <:col :let={m} label="Positions">
          <form id={"positions-form-#{m.id}"} phx-change="update_positions" phx-value-id={m.id}>
            <input type="hidden" name="position_ids[]" value="" />
            <button
              type="button"
              class="btn btn-sm btn-outline max-w-56 justify-between gap-2 font-normal"
              popovertarget={"positions-popover-#{m.id}"}
              style={"anchor-name:--positions-anchor-#{m.id}"}
              aria-label={"Positions held by #{m.name}: #{position_summary(m)}"}
            >
              <span class="truncate">{position_summary(m)}</span>
              <.icon name="hero-chevron-down" class="size-4 shrink-0" />
            </button>
            <fieldset
              id={"positions-popover-#{m.id}"}
              popover
              class="dropdown w-64 rounded-box border border-base-300 bg-base-100 p-2 shadow-md"
              style={"position-anchor:--positions-anchor-#{m.id}"}
            >
              <legend class="sr-only">Positions held by {m.name}</legend>
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
            </fieldset>
          </form>
        </:col>
        <:action :let={m}>
          <button
            :if={m.status == :approved}
            type="button"
            class="link link-hover"
            phx-click="show_reason"
            phx-value-id={m.id}
            phx-value-to="inactive"
          >
            Deactivate
          </button>
          <button
            :if={m.status == :inactive}
            type="button"
            class="link link-hover"
            phx-click="approve"
            phx-value-id={m.id}
          >Reactivate</button>
          <button
            :if={m.status == :rejected}
            type="button"
            class="link link-hover"
            phx-click="reopen"
            phx-value-id={m.id}
          >Reopen</button>
        </:action>
        <:action :let={m}>
          <button type="button" class="link link-hover" phx-click="show_audit" phx-value-id={m.id}>Audit</button>
        </:action>
      </.table>

      <.modal
        :if={@reason_for}
        id="reason-modal"
        title={if @reason_for.to == "inactive", do: "Deactivate member", else: "Reject member"}
        on_close="cancel_reason"
      >
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
      </.modal>

      <.modal
        :if={@audit_for}
        id="audit-modal"
        title={"Audit trail — #{@audit_for.call_sign || @audit_for.name}"}
        on_close="close_audit"
      >
        <ul class="list bg-base-100 rounded-box border border-base-300">
          <li :for={a <- Members.list_audit_for_member(@audit_for.id)} class="list-row">
            {a.from_status} <span class="sr-only">to</span><span aria-hidden="true">&rarr;</span>
            {a.to_status} &middot; {a.inserted_at}
            <span :if={a.reason}> &mdash; {a.reason}</span>
          </li>
        </ul>
        <div class="modal-action">
          <button type="button" phx-click="close_audit" class="btn btn-ghost">Close</button>
        </div>
      </.modal>
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
        {:noreply, load_members(socket)}

      {:error, :not_approved} ->
        {:noreply,
         socket
         |> put_flash(:error, "Only approved members can hold positions.")
         |> load_members()}
    end
  end

  defp load_members(socket) do
    {pending, others} = Enum.split_with(Members.list_members(), &(&1.status == :pending))
    assign(socket, pending_members: pending, members: others)
  end

  defp position_summary(%{positions: []}), do: "None"
  defp position_summary(%{positions: positions}), do: Enum.map_join(positions, ", ", & &1.name)

  defp transition(socket, member, to_status, reason) do
    actor = socket.assigns.current_scope.user

    case Members.transition_status(member, to_status, actor, reason) do
      {:ok, _} ->
        {:noreply, load_members(socket)}

      {:error, :illegal_transition} ->
        {:noreply, put_flash(socket, :error, "That status change isn't allowed.")}

      {:error, changeset} ->
        {:noreply, put_flash(socket, :error, "Error: #{inspect(changeset.errors)}")}
    end
  end
end
