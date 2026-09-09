defmodule McEmcommWeb.OperationLive.Show do
  use McEmcommWeb, :live_view

  alias McEmcomm.Operations
  alias McEmcomm.Operations.OperationRsvp
  alias McEmcomm.Storage
  alias McEmcommWeb.MapHelpers
  alias McEmcommWeb.ParamHelpers

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    operation = Operations.get_operation!(id)
    member = socket.assigns.current_scope.member

    {:ok,
     socket
     |> assign(
       page_title: operation.title,
       operation: operation,
       member: member,
       markers_json: markers_json(operation),
       tile_url: MapHelpers.tile_url()
     )
     |> assign_rsvps()}
  end

  @response_labels [yes: "Going", maybe: "Maybe", no: "Not going"]
  @response_options Enum.map(@response_labels, fn {value, label} -> {label, value} end)

  defp assign_rsvps(socket) do
    operation = socket.assigns.operation
    member = socket.assigns.member
    rsvps = Operations.list_rsvps(operation.id)
    own = member && Enum.find(rsvps, &(&1.member_id == member.id))

    assign(socket,
      rsvps: rsvps,
      rsvp_counts: Operations.rsvp_counts(rsvps),
      own_rsvp: own,
      rsvp_open?: not Operations.ended?(operation),
      rsvp_form: to_form(Operations.change_rsvp(own || %OperationRsvp{}))
    )
  end

  defp response_label(response), do: Keyword.fetch!(@response_labels, response)

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} active_net={@active_net}>
      <.header>
        {@operation.title}
        <:subtitle>
          {Calendar.strftime(@operation.starts_at, "%B %d, %Y %I:%M %p")} &ndash; {Calendar.strftime(
            @operation.ends_at,
            "%I:%M %p"
          )}
          <span class="badge badge-sm badge-ghost ml-2">{@operation.visibility}</span>
        </:subtitle>
        <:actions>
          <.button
            :if={@member && @member.status == :approved}
            phx-click="mark_attendance"
            class="btn btn-primary"
          >
            Mark my attendance
          </.button>
        </:actions>
      </.header>

      <p :if={@operation.description}>{@operation.description}</p>

      <h2 class="text-lg font-semibold mt-6">Locations</h2>
      <.static_map
        :if={@operation.locations != []}
        id="operation-map"
        label={"Map of #{@operation.title} locations"}
        markers_json={@markers_json}
        tile_url={@tile_url}
      />
      <ul class="mt-2 space-y-1">
        <li :for={loc <- @operation.locations} class="text-sm">
          <strong>{loc.name}</strong>
          &middot; geofence {loc.geofence_radius_m}m
          <span :if={loc.notes} class="text-base-content/70"> &mdash; {loc.notes}</span>
        </li>
      </ul>

      <h2 class="text-lg font-semibold mt-6">Attachments</h2>
      <ul
        :if={@operation.attachments != []}
        class="list bg-base-100 rounded-box border border-base-300"
      >
        <li :for={att <- @operation.attachments} class="list-row items-center">
          <div class="flex-1">
            <div class="font-semibold">{att.filename}</div>
            <div class="text-sm text-base-content/70">{att.description}</div>
          </div>
          <button
            type="button"
            class="btn btn-sm btn-outline"
            phx-click="download_attachment"
            phx-value-id={att.id}
            aria-label={"Download #{att.filename}"}
          >
            Download
          </button>
        </li>
      </ul>
      <p :if={@operation.attachments == []} class="text-base-content/70">No attachments.</p>

      <h2 class="text-lg font-semibold mt-6">RSVPs</h2>
      <p id="rsvp-counts" class="text-sm text-base-content/70">
        <span id="rsvp-count-yes">Going: {@rsvp_counts.yes}</span>
        &middot; <span id="rsvp-count-maybe">Maybe: {@rsvp_counts.maybe}</span>
        &middot; <span id="rsvp-count-no">Not going: {@rsvp_counts.no}</span>
      </p>

      <%= cond do %>
        <% @member && @member.status == :approved && @rsvp_open? -> %>
          <.form
            for={@rsvp_form}
            id="rsvp-form"
            phx-submit="rsvp"
            class="mt-2 max-w-md"
            aria-label="Your RSVP"
          >
            <p :if={@own_rsvp} id="rsvp-status" class="text-sm mb-2">
              You replied <strong>{response_label(@own_rsvp.response)}</strong>.
            </p>
            <.input
              field={@rsvp_form[:response]}
              type="select"
              label="Will you be there?"
              options={rsvp_options()}
              prompt="Choose a response"
            />
            <.input
              field={@rsvp_form[:note]}
              type="text"
              label="Note (optional)"
              placeholder="e.g. available after 1400"
              maxlength={OperationRsvp.note_max_length()}
            />
            <.button id="rsvp-submit" class="btn btn-primary btn-sm">
              {if @own_rsvp, do: "Update RSVP", else: "Save RSVP"}
            </.button>
          </.form>
        <% @member && @member.status == :approved -> %>
          <p id="rsvp-closed" class="text-sm text-base-content/70 mt-2">
            RSVPs closed when the operation ended.
          </p>
        <% true -> %>
      <% end %>

      <ul
        :if={@rsvps != []}
        id="rsvps"
        class="list bg-base-100 rounded-box border border-base-300 mt-2"
      >
        <li :for={r <- @rsvps} id={"rsvp-#{r.id}"} class="list-row">
          <div class="flex-1">
            {r.member.name} <span :if={r.member.call_sign}>({r.member.call_sign})</span>
            <span class="badge badge-sm badge-ghost ml-2">{response_label(r.response)}</span>
            <div :if={r.note} class="text-sm text-base-content/70">{r.note}</div>
          </div>
        </li>
      </ul>
      <p :if={@rsvps == []} id="rsvps-empty" class="text-base-content/70">No RSVPs yet.</p>

      <h2 class="text-lg font-semibold mt-6">Attendance</h2>
      <ul
        :if={@operation.attendance != []}
        class="list bg-base-100 rounded-box border border-base-300"
      >
        <li :for={a <- @operation.attendance} class="list-row">
          {a.member.name} <span :if={a.member.call_sign}>({a.member.call_sign})</span>
          <span class="badge badge-sm badge-ghost ml-2">{a.source}</span>
        </li>
      </ul>
      <p :if={@operation.attendance == []} class="text-base-content/70">
        No recorded attendance yet.
      </p>

      <.link navigate={~p"/app/operations"} class="link mt-4 inline-block">&larr; Back to operations</.link>
    </Layouts.app>
    """
  end

  @impl true
  def handle_event("rsvp", %{"operation_rsvp" => params}, socket) do
    case Operations.rsvp(socket.assigns.operation, socket.assigns.member.id, params) do
      {:ok, _rsvp} ->
        {:noreply,
         socket
         |> put_flash(:info, "RSVP saved.")
         |> assign_rsvps()}

      {:error, :operation_ended} ->
        {:noreply,
         socket
         |> put_flash(:error, "RSVPs closed when the operation ended.")
         |> assign_rsvps()}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, rsvp_form: to_form(changeset))}
    end
  end

  def handle_event("mark_attendance", _params, socket) do
    member = socket.assigns.member

    case Operations.record_attendance(socket.assigns.operation.id, member.id, :manual) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Attendance recorded.")
         |> assign(operation: Operations.get_operation!(socket.assigns.operation.id))}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not record attendance.")}
    end
  end

  def handle_event("download_attachment", %{"id" => id}, socket) do
    id = ParamHelpers.id(id)

    case Enum.find(socket.assigns.operation.attachments, &(&1.id == id)) do
      nil ->
        {:noreply, put_flash(socket, :error, "That attachment is no longer available.")}

      attachment ->
        {:noreply, redirect(socket, external: Storage.presign_download_url(attachment.key))}
    end
  end

  defp rsvp_options, do: @response_options

  defp markers_json(operation) do
    operation.locations
    |> Enum.map(&%{point: &1.point, title: &1.name, radius_m: &1.geofence_radius_m})
    |> MapHelpers.markers_json()
  end
end
