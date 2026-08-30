defmodule McEmcommWeb.AdminLive.MemberIndex do
  @moduledoc "Membership approvals, role editing, and the membership_audit trail (§9 Admin approval)."

  use McEmcommWeb, :live_view

  alias McEmcomm.Members
  alias McEmcomm.Members.Member

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: "Members",
       members: Members.list_members(),
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
        <:col :let={m} label="Role">
          <form phx-change="update_role" phx-value-id={m.id}>
            <select name="role" class="select select-sm">
              <option :for={role <- Member.roles()} value={role} selected={role == m.role}>
                {Phoenix.Naming.humanize(role)}
              </option>
            </select>
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

      <div :if={@reason_for} class="mt-4 max-w-md">
        <.form
          for={to_form(%{"reason" => ""}, as: "transition")}
          id="reason-form"
          phx-submit="do_transition"
        >
          <input type="hidden" name="transition[id]" value={@reason_for.id} />
          <input type="hidden" name="transition[to]" value={@reason_for.to} />
          <.input name="transition[reason]" value="" label={"Reason for #{@reason_for.to}"} required />
          <.button class="btn btn-primary mt-2">Confirm</.button>
          <button type="button" phx-click="cancel_reason" class="btn btn-ghost mt-2">Cancel</button>
        </.form>
      </div>

      <div :if={@audit_for} class="mt-6 max-w-lg">
        <h2 class="text-lg font-semibold">Audit trail</h2>
        <ul class="list bg-base-100 rounded-box border border-base-300">
          <li :for={a <- Members.list_audit_for_member(@audit_for)} class="list-row">
            {a.from_status} &rarr; {a.to_status} &middot; {a.inserted_at}
            <span :if={a.reason}> &mdash; {a.reason}</span>
          </li>
        </ul>
      </div>
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
    transition(socket, Members.get_member!(id), String.to_existing_atom(to), reason)
  end

  def handle_event("show_audit", %{"id" => id}, socket) do
    {:noreply, assign(socket, audit_for: String.to_integer(id))}
  end

  def handle_event("update_role", %{"id" => id, "role" => role}, socket) do
    member = Members.get_member!(id)
    Members.update_role(member, %{role: role})
    {:noreply, assign(socket, members: Members.list_members())}
  end

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
