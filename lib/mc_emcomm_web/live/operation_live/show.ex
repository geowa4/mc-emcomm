defmodule McEmcommWeb.OperationLive.Show do
  use McEmcommWeb, :live_view

  alias McEmcomm.Operations
  alias McEmcomm.Storage
  alias McEmcommWeb.MapHelpers
  alias McEmcommWeb.ParamHelpers

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    operation = Operations.get_operation!(id)
    member = socket.assigns.current_scope.member

    {:ok,
     assign(socket,
       page_title: operation.title,
       operation: operation,
       member: member,
       markers_json: markers_json(operation),
       tile_url: MapHelpers.tile_url()
     )}
  end

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

  defp markers_json(operation) do
    operation.locations
    |> Enum.map(&%{point: &1.point, title: &1.name, radius_m: &1.geofence_radius_m})
    |> MapHelpers.markers_json()
  end
end
