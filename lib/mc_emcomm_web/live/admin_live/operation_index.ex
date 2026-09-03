defmodule McEmcommWeb.AdminLive.OperationIndex do
  use McEmcommWeb, :live_view

  alias McEmcomm.Operations
  alias McEmcomm.Operations.Operation
  alias McEmcomm.Operations.OperationLocation
  alias McEmcomm.Storage
  alias McEmcommWeb.MapHelpers
  alias McEmcommWeb.ParamHelpers

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(page_title: "Operations", operations: Operations.list_operations())
     |> allow_upload(:attachment, accept: :any, max_entries: 1, external: &presign_entry/2)}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params) do
    assign(socket, operation: nil, form: nil, location_form: nil)
  end

  defp apply_action(socket, :new, _params) do
    assign(socket,
      operation: %Operation{locations: [], attachments: []},
      form: to_form(Operations.change_operation(%Operation{})),
      location_form: nil
    )
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    operation = Operations.get_operation!(id)

    assign(socket,
      operation: operation,
      form: to_form(Operations.change_operation(operation)),
      location_form: to_form(Operations.change_operation_location(%OperationLocation{})),
      pending_point: nil,
      markers_json: markers_json(operation),
      tile_url: MapHelpers.tile_url()
    )
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} active_net={@active_net}>
      <.header>
        Operations
        <:actions>
          <.link
            :if={@live_action == :index}
            navigate={~p"/admin/operations/new"}
            class="btn btn-primary"
          >
            New operation
          </.link>
        </:actions>
      </.header>

      <.table
        :if={@live_action == :index}
        id="operations"
        rows={@operations}
        row_click={fn e -> JS.navigate(~p"/admin/operations/#{e.id}/edit") end}
      >
        <:col :let={e} label="Title">{e.title}</:col>
        <:col :let={e} label="Starts">{Calendar.strftime(e.starts_at, "%Y-%m-%d %H:%M")}</:col>
        <:col :let={e} label="Visibility">{e.visibility}</:col>
        <:action :let={e}>
          <.link phx-click="delete" phx-value-id={e.id} data-confirm="Delete this operation?">
            Delete
          </.link>
        </:action>
      </.table>

      <div :if={@live_action in [:new, :edit]} class="max-w-lg">
        <.form for={@form} id="operation-form" phx-change="validate" phx-submit="save">
          <.input field={@form[:title]} label="Title" required />
          <.input field={@form[:description]} type="textarea" label="Description" />
          <.input field={@form[:starts_at]} type="datetime-local" label="Starts at" required />
          <.input field={@form[:ends_at]} type="datetime-local" label="Ends at" required />
          <.input
            field={@form[:visibility]}
            type="select"
            label="Visibility"
            options={Enum.map(Operation.visibilities(), &{Phoenix.Naming.humanize(&1), &1})}
          />
          <.button phx-disable-with="Saving..." class="btn btn-primary mt-2">Save operation</.button>
        </.form>

        <div :if={@live_action == :edit}>
          <h2 class="text-lg font-semibold mt-8">Locations</h2>
          <div
            id="location-map"
            phx-hook="LeafletPicker"
            phx-update="ignore"
            class="map-canvas"
            data-tile-url={@tile_url}
          >
          </div>
          <p class="text-sm text-base-content/70 mt-1">
            Click the map to place a point for the new location below.
            <span :if={@pending_point} class="font-mono">
              ({elem(@pending_point, 0)}, {elem(@pending_point, 1)})
            </span>
          </p>

          <.form
            for={@location_form}
            id="location-form"
            phx-submit="add_location"
            class="mt-2 flex gap-2 items-end flex-wrap"
          >
            <.input field={@location_form[:name]} label="Name (blank = Primary Site)" />
            <.input
              field={@location_form[:geofence_radius_m]}
              type="number"
              label="Radius (m)"
              value="500"
            />
            <.button class="btn btn-secondary mb-3" disabled={is_nil(@pending_point)}>
              Add location
            </.button>
          </.form>

          <ul class="list bg-base-100 rounded-box border border-base-300 mt-2">
            <li :for={loc <- @operation.locations} class="list-row">
              <div class="flex-1">
                <strong>{loc.name}</strong> &middot; {loc.geofence_radius_m}m
              </div>
              <.link
                phx-click="delete_location"
                phx-value-id={loc.id}
                data-confirm="Remove this location?"
              >
                Remove
              </.link>
            </li>
          </ul>

          <h2 class="text-lg font-semibold mt-8">Attachments</h2>
          <form id="attachment-form" phx-change="validate_attachment" phx-submit="save_attachment">
            <.live_file_input upload={@uploads.attachment} />
            <.input
              name="description"
              value=""
              label="Description (required)"
              id="attachment-description"
            />
            <.button class="btn btn-secondary mt-2">Upload attachment</.button>
          </form>

          <ul class="list bg-base-100 rounded-box border border-base-300 mt-2">
            <li :for={att <- @operation.attachments} class="list-row">
              <div class="flex-1">
                <div class="font-semibold">{att.filename}</div>
                <div class="text-sm text-base-content/70">{att.description}</div>
              </div>
              <.link
                phx-click="delete_attachment"
                phx-value-id={att.id}
                data-confirm="Delete this attachment?"
              >
                Delete
              </.link>
            </li>
          </ul>
        </div>

        <.link navigate={~p"/admin/operations"} class="link mt-6 inline-block">&larr; Back to operations</.link>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def handle_event("validate", %{"operation" => params}, socket) do
    form =
      socket.assigns.operation
      |> Operations.change_operation(params)
      |> Map.put(:action, :validate)
      |> to_form()

    {:noreply, assign(socket, form: form)}
  end

  def handle_event("save", %{"operation" => params}, socket) do
    save_operation(socket, socket.assigns.live_action, params)
  end

  def handle_event("delete", %{"id" => id}, socket) do
    Operations.get_operation!(id) |> Operations.delete_operation()
    {:noreply, assign(socket, operations: Operations.list_operations())}
  end

  def handle_event("point_selected", %{"lat" => lat, "lng" => lng}, socket) do
    {:noreply, assign(socket, pending_point: {lat, lng})}
  end

  def handle_event("add_location", %{"operation_location" => params}, socket) do
    operation = socket.assigns.operation
    {lat, lng} = socket.assigns[:pending_point] || {nil, nil}

    name =
      case params["name"] do
        "" -> if operation.locations == [], do: "Primary Site", else: nil
        name -> name
      end

    attrs = %{
      "operation_id" => operation.id,
      "name" => name,
      "geofence_radius_m" => params["geofence_radius_m"],
      "point" => lat && lng && McEmcommWeb.MapHelpers.point(lat, lng)
    }

    case Operations.create_operation_location(attrs) do
      {:ok, _location} ->
        operation = Operations.get_operation!(operation.id)

        {:noreply,
         assign(socket,
           operation: operation,
           markers_json: markers_json(operation),
           location_form: to_form(Operations.change_operation_location(%OperationLocation{})),
           pending_point: nil
         )}

      {:error, changeset} ->
        {:noreply, assign(socket, location_form: to_form(changeset))}
    end
  end

  def handle_event("delete_location", %{"id" => id}, socket) do
    operation = socket.assigns.operation
    id = ParamHelpers.id(id)
    location = Enum.find(operation.locations, &(&1.id == id))
    location && Operations.delete_operation_location(location)
    operation = Operations.get_operation!(operation.id)
    {:noreply, assign(socket, operation: operation, markers_json: markers_json(operation))}
  end

  def handle_event("delete_attachment", %{"id" => id}, socket) do
    operation = socket.assigns.operation
    id = ParamHelpers.id(id)
    att = Enum.find(operation.attachments, &(&1.id == id))
    att && Operations.delete_operation_attachment(att)
    {:noreply, assign(socket, operation: Operations.get_operation!(operation.id))}
  end

  def handle_event("validate_attachment", _params, socket), do: {:noreply, socket}

  def handle_event("save_attachment", %{"description" => description}, socket) do
    operation = socket.assigns.operation

    uploaded =
      consume_uploaded_entries(socket, :attachment, fn %{key: key}, entry ->
        {:ok, %{key: key, filename: entry.client_name, content_type: entry.client_type}}
      end)

    case uploaded do
      [%{key: key, filename: filename, content_type: content_type}] ->
        attrs = %{
          operation_id: operation.id,
          key: key,
          filename: filename,
          content_type: content_type,
          description: description,
          uploaded_by_id: socket.assigns.current_scope.user.id
        }

        case Operations.create_operation_attachment(attrs) do
          {:ok, _} ->
            {:noreply, assign(socket, operation: Operations.get_operation!(operation.id))}

          {:error, changeset} ->
            {:noreply,
             put_flash(socket, :error, "Attachment error: #{inspect(changeset.errors)}")}
        end

      [] ->
        {:noreply, put_flash(socket, :error, "Choose a file first.")}
    end
  end

  defp save_operation(socket, :new, params) do
    params = Map.put(params, "created_by_id", socket.assigns.current_scope.user.id)

    case Operations.create_operation(params) do
      {:ok, operation} ->
        {:noreply,
         socket
         |> put_flash(:info, "Operation created.")
         |> push_navigate(to: ~p"/admin/operations/#{operation.id}/edit")}

      {:error, changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp save_operation(socket, :edit, params) do
    case Operations.update_operation(socket.assigns.operation, params) do
      {:ok, operation} ->
        {:noreply,
         socket
         |> put_flash(:info, "Operation updated.")
         |> assign(
           operation: Operations.get_operation!(operation.id),
           form: to_form(Operations.change_operation(operation))
         )}

      {:error, changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp presign_entry(entry, socket) do
    key = Storage.build_key("operation-attachments", entry.client_name)
    presigned = Storage.presign_upload(key, entry.client_type)
    meta = %{uploader: "S3", key: key, url: presigned.url, fields: presigned.fields}
    {:ok, meta, socket}
  end

  defp markers_json(operation) do
    operation.locations
    |> Enum.map(&%{point: &1.point, title: &1.name, radius_m: &1.geofence_radius_m})
    |> MapHelpers.markers_json()
  end
end
