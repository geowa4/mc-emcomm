defmodule McEmcommWeb.ExerciseLive.Show do
  use McEmcommWeb, :live_view

  alias McEmcomm.Exercises
  alias McEmcomm.Storage
  alias McEmcommWeb.MapHelpers
  alias McEmcommWeb.ParamHelpers

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    exercise = Exercises.get_exercise!(id)
    member = socket.assigns.current_scope.member

    {:ok,
     assign(socket,
       page_title: exercise.title,
       exercise: exercise,
       member: member,
       markers_json: markers_json(exercise),
       tile_url: MapHelpers.tile_url()
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        {@exercise.title}
        <:subtitle>
          {Calendar.strftime(@exercise.starts_at, "%B %d, %Y %I:%M %p")} &ndash; {Calendar.strftime(
            @exercise.ends_at,
            "%I:%M %p"
          )}
          <span class="badge badge-sm badge-ghost ml-2">{@exercise.visibility}</span>
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

      <p :if={@exercise.description}>{@exercise.description}</p>

      <h2 class="text-lg font-semibold mt-6">Locations</h2>
      <div
        :if={@exercise.locations != []}
        id="exercise-map"
        phx-hook="LeafletMap"
        phx-update="ignore"
        class="map-canvas"
        data-markers={@markers_json}
        data-tile-url={@tile_url}
      >
      </div>
      <ul class="mt-2 space-y-1">
        <li :for={loc <- @exercise.locations} class="text-sm">
          <strong>{loc.name}</strong>
          &middot; geofence {loc.geofence_radius_m}m
          <span :if={loc.notes} class="text-base-content/70"> &mdash; {loc.notes}</span>
        </li>
      </ul>

      <h2 class="text-lg font-semibold mt-6">Attachments</h2>
      <ul
        :if={@exercise.attachments != []}
        class="list bg-base-100 rounded-box border border-base-300"
      >
        <li :for={att <- @exercise.attachments} class="list-row items-center">
          <div class="flex-1">
            <div class="font-semibold">{att.filename}</div>
            <div class="text-sm text-base-content/70">{att.description}</div>
          </div>
          <button class="btn btn-sm btn-outline" phx-click="download_attachment" phx-value-id={att.id}>
            Download
          </button>
        </li>
      </ul>
      <p :if={@exercise.attachments == []} class="text-base-content/70">No attachments.</p>

      <h2 class="text-lg font-semibold mt-6">Attendance</h2>
      <ul :if={@exercise.attendance != []} class="list bg-base-100 rounded-box border border-base-300">
        <li :for={a <- @exercise.attendance} class="list-row">
          {a.member.name} <span :if={a.member.call_sign}>({a.member.call_sign})</span>
          <span class="badge badge-sm badge-ghost ml-2">{a.source}</span>
        </li>
      </ul>
      <p :if={@exercise.attendance == []} class="text-base-content/70">No recorded attendance yet.</p>

      <.link navigate={~p"/app/exercises"} class="link mt-4 inline-block">&larr; Back to exercises</.link>
    </Layouts.app>
    """
  end

  @impl true
  def handle_event("mark_attendance", _params, socket) do
    member = socket.assigns.member

    case Exercises.record_attendance(socket.assigns.exercise.id, member.id, :manual) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Attendance recorded.")
         |> assign(exercise: Exercises.get_exercise!(socket.assigns.exercise.id))}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not record attendance.")}
    end
  end

  def handle_event("download_attachment", %{"id" => id}, socket) do
    id = ParamHelpers.id(id)

    case Enum.find(socket.assigns.exercise.attachments, &(&1.id == id)) do
      nil ->
        {:noreply, put_flash(socket, :error, "That attachment is no longer available.")}

      attachment ->
        {:noreply, redirect(socket, external: Storage.presign_download_url(attachment.key))}
    end
  end

  defp markers_json(exercise) do
    exercise.locations
    |> Enum.map(&%{point: &1.point, title: &1.name, radius_m: &1.geofence_radius_m})
    |> MapHelpers.markers_json()
  end
end
