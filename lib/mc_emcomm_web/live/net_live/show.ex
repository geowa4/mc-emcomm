defmodule McEmcommWeb.NetLive.Show do
  use McEmcommWeb, :live_view

  alias McEmcomm.Locations
  alias McEmcomm.Members
  alias McEmcomm.Members.Member
  alias McEmcomm.Net
  alias McEmcomm.Net.NetCheckin
  alias McEmcomm.Operations
  alias McEmcommWeb.MapHelpers

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    session = Net.get_session!(id)

    if connected?(socket), do: Net.subscribe(session.id)

    {:ok,
     socket
     |> assign(
       page_title: session.name || "Net ##{session.id}",
       session: session,
       editing_name?: false,
       name_form: to_form(%{"name" => session.name}, as: :net_session),
       editing_aprs_keyword?: false,
       aprs_keyword_form: to_form(Net.change_session(session)),
       checkin_form: to_form(Net.change_checkin(%NetCheckin{})),
       editing_checkin: nil,
       edit_checkin_form: nil,
       default_locations: Locations.list_default_locations(),
       operations: Operations.list_operations(),
       editing_operation?: false,
       ncs_modal?: false,
       ncs_query: "",
       ncs_results: nil,
       tile_url: MapHelpers.tile_url()
     )
     |> assign_markers()}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        <%= if @editing_name? do %>
          <.form
            for={@name_form}
            id="net-name-form"
            phx-submit="rename_session"
            class="flex flex-wrap gap-2 items-center"
          >
            <.input field={@name_form[:name]} />
            <.button class="btn btn-primary btn-sm">Save</.button>
            <button type="button" phx-click="cancel_edit_name" class="btn btn-ghost btn-sm">
              Cancel
            </button>
          </.form>
        <% else %>
          {@session.name || "Net ##{@session.id}"}
          <button
            id="edit-net-name"
            phx-click="edit_name"
            class="btn btn-ghost btn-xs align-middle"
            title="Edit net name"
          >
            <.icon name="hero-pencil-square" class="size-4" />
          </button>
        <% end %>
        <:subtitle>Started {Calendar.strftime(@session.started_at, "%Y-%m-%d %H:%M")}</:subtitle>
        <:actions>
          <.button
            :if={is_nil(@session.ended_at)}
            phx-click="end_session"
            class="btn btn-outline btn-sm"
          >
            End net
          </.button>
        </:actions>
      </.header>

      <div id="net-control" class="mt-2 flex flex-wrap items-center gap-2">
        <span class="font-semibold">Net control:</span>
        <span :if={@session.net_control_member}>
          {@session.net_control_member.name}<span :if={@session.net_control_member.call_sign}> &middot; <span class="font-mono">{@session.net_control_member.call_sign}</span></span>
        </span>
        <span :if={is_nil(@session.net_control_member)} class="text-base-content/50 italic">
          Vacant
        </span>
        <%= if is_nil(@session.ended_at) do %>
          <button
            :if={not net_control?(@current_scope, @session)}
            id="take-net-control"
            phx-click="take_net_control"
            class="btn btn-outline btn-xs"
          >
            Take net control
          </button>
          <button id="change-net-control" phx-click="open_ncs_modal" class="btn btn-ghost btn-xs">
            Change
          </button>
          <button
            :if={@session.net_control_member}
            id="vacate-net-control"
            phx-click="vacate_net_control"
            data-confirm="Vacate net control?"
            class="btn btn-ghost btn-xs"
          >
            Vacate
          </button>
        <% end %>
      </div>

      <div id="net-operation" class="mt-1 flex flex-wrap items-center gap-2">
        <%= if @editing_operation? do %>
          <form id="net-operation-form" phx-submit="assign_operation" class="flex gap-2 items-end">
            <.input
              type="select"
              id="net-operation-select"
              name="operation_id"
              value={@session.operation_id}
              label="Operation"
              prompt="No operation"
              options={Enum.map(@operations, &{operation_option_label(&1), &1.id})}
            />
            <.button class="btn btn-primary btn-sm mb-3">Save</.button>
            <button
              type="button"
              phx-click="cancel_edit_operation"
              class="btn btn-ghost btn-sm mb-3"
            >
              Cancel
            </button>
          </form>
        <% else %>
          <span class="font-semibold">Operation:</span>
          <span :if={@session.operation}>
            <.link navigate={~p"/app/operations/#{@session.operation.id}"} class="link link-hover">
              {@session.operation.title}
            </.link>
          </span>
          <span :if={is_nil(@session.operation)} class="text-base-content/50 italic">None</span>
          <button
            :if={is_nil(@session.ended_at)}
            id="edit-net-operation"
            phx-click="edit_operation"
            class="btn btn-ghost btn-xs"
            title="Assign operation"
          >
            <.icon name="hero-pencil-square" class="size-4" />
          </button>
        <% end %>
      </div>

      <div id="net-aprs-keyword" class="mt-1 flex flex-wrap items-center gap-2">
        <%= if @editing_aprs_keyword? do %>
          <.form
            for={@aprs_keyword_form}
            id="net-aprs-keyword-form"
            phx-submit="update_aprs_keyword"
            class="flex gap-2 items-end"
          >
            <.input
              field={@aprs_keyword_form[:aprs_keyword]}
              id="net-aprs-keyword-input"
              label="APRS keyword"
            />
            <.button class="btn btn-primary btn-sm mb-3">Save</.button>
            <button
              type="button"
              phx-click="cancel_edit_aprs_keyword"
              class="btn btn-ghost btn-sm mb-3"
            >
              Cancel
            </button>
          </.form>
        <% else %>
          <span class="font-semibold">APRS keyword:</span>
          <span class="font-mono">{@session.aprs_keyword}</span>
          <button
            :if={is_nil(@session.ended_at)}
            id="edit-net-aprs-keyword"
            phx-click="edit_aprs_keyword"
            class="btn btn-ghost btn-xs"
            title="Edit APRS keyword"
          >
            <.icon name="hero-pencil-square" class="size-4" />
          </button>
          <span class="text-sm text-base-content/70">
            Stations beaconing it in an APRS position comment are checked in here.
          </span>
        <% end %>
      </div>

      <dialog
        :if={@ncs_modal?}
        id="ncs-modal"
        class="modal modal-open"
        phx-window-keydown="close_ncs_modal"
        phx-key="escape"
      >
        <div class="modal-box">
          <h3 class="text-lg font-semibold mb-2">Change net control</h3>
          <form id="ncs-search-form" phx-submit="search_ncs">
            <.input
              name="call_sign"
              value={@ncs_query}
              label="Call sign"
              placeholder="Full or partial call sign, then Enter"
              phx-mounted={JS.focus()}
              autocomplete="off"
            />
          </form>
          <ul
            :if={@ncs_results}
            id="ncs-results"
            class="menu bg-base-100 rounded-box border border-base-300 mt-2 w-full"
          >
            <li :if={@ncs_results == []} class="menu-title">No members match that call sign.</li>
            <li :for={member <- @ncs_results}>
              <button type="button" phx-click="assign_net_control" phx-value-member-id={member.id}>
                <span class="font-mono">{member.call_sign}</span>
                {member.name}
              </button>
            </li>
          </ul>
          <div class="modal-action">
            <button type="button" phx-click="close_ncs_modal" class="btn btn-ghost">Close</button>
          </div>
        </div>
        <button
          type="button"
          class="modal-backdrop"
          phx-click="close_ncs_modal"
          aria-label="Close"
        ></button>
      </dialog>

      <.form
        :if={is_nil(@session.ended_at)}
        for={@checkin_form}
        id="checkin-form"
        phx-submit="check_in"
        phx-hook=".ResetOnSave"
        class="flex gap-2 items-end flex-wrap mt-4"
      >
        <.input field={@checkin_form[:call_sign]} label="Call sign" required />
        <.input
          type="select"
          id="checkin-location"
          name="location_ref"
          value=""
          label="Location"
          options={location_options(@session, @default_locations)}
        />
        <.input field={@checkin_form[:notes]} label="Notes" />
        <.button class="btn btn-primary mb-3">Check in</.button>
      </.form>
      <script :type={Phoenix.LiveView.ColocatedHook} name=".ResetOnSave">
        export default {
          mounted() {
            this.handleEvent("checkin_saved", () => {
              this.el.reset()
              const callSign = this.el.elements["net_checkin[call_sign]"]
              if (!callSign) return
              // LiveView refocuses the submit button after the ack, at an
              // unpredictable point after this event; redirect that focus to
              // the call sign field for a short window.
              const redirect = (e) => { if (e.target !== callSign) callSign.focus() }
              this.el.addEventListener("focusin", redirect)
              requestAnimationFrame(() => callSign.focus())
              setTimeout(() => this.el.removeEventListener("focusin", redirect), 300)
            })
          }
        }
      </script>

      <h2 class="text-lg font-semibold mt-8">Roster</h2>

      <dialog
        :if={@editing_checkin}
        id="edit-checkin-modal"
        class="modal modal-open"
        phx-window-keydown="cancel_edit_checkin"
        phx-key="escape"
      >
        <div class="modal-box">
          <h3 class="text-lg font-semibold mb-2">Edit check-in</h3>
          <.form for={@edit_checkin_form} id="edit-checkin-form" phx-submit="update_checkin">
            <.input
              field={@edit_checkin_form[:call_sign]}
              id="edit-checkin-call-sign"
              label="Call sign"
              required
            />
            <.input
              type="select"
              id="edit-checkin-location"
              name="location_ref"
              value=""
              label="Location"
              options={edit_location_options(@session, @default_locations, @editing_checkin)}
            />
            <.input field={@edit_checkin_form[:notes]} id="edit-checkin-notes" label="Notes" />
            <div class="modal-action">
              <button type="button" phx-click="cancel_edit_checkin" class="btn btn-ghost">
                Cancel
              </button>
              <.button class="btn btn-primary">Save</.button>
            </div>
          </.form>
        </div>
        <button
          type="button"
          class="modal-backdrop"
          phx-click="cancel_edit_checkin"
          aria-label="Close"
        ></button>
      </dialog>

      <.table id="checkins" rows={@session.checkins} row_id={&"checkin-row-#{&1.id}"}>
        <:col :let={c} label="Call sign">
          {c.call_sign}
          <span
            :if={c.aprs_call_sign}
            id={"checkin-aprs-#{c.id}"}
            class="badge badge-outline badge-xs ml-1"
            title="Position via APRS-IS"
          >
            APRS · {c.aprs_call_sign}
          </span>
        </:col>
        <:col :let={c} label="Member">{c.member && c.member.name}</:col>
        <:col :let={c} label="Location">{c.location_name}</:col>
        <:col :let={c} label="Notes">{c.notes}</:col>
        <:col :let={c} label="Joined">{Calendar.strftime(c.recorded_at, "%H:%M:%S")}</:col>
        <:col :let={c} label="Left">
          {c.ended_at && Calendar.strftime(c.ended_at, "%H:%M:%S")}
        </:col>
        <:col :let={c} label="Duration">{format_duration(c)}</:col>
        <:action :let={c}>
          <button
            id={"edit-checkin-#{c.id}"}
            phx-click="edit_checkin"
            phx-value-id={c.id}
            class="btn btn-ghost btn-xs"
            title="Edit check-in"
          >
            <.icon name="hero-pencil-square" class="size-4" />
          </button>
          <button
            :if={is_nil(c.ended_at) and is_nil(@session.ended_at)}
            id={"checkout-checkin-#{c.id}"}
            phx-click="check_out"
            phx-value-id={c.id}
            class="btn btn-ghost btn-xs"
            title="Log leaving the net"
          >
            Leave
          </button>
        </:action>
      </.table>

      <h2 class="text-lg font-semibold mt-8">On-net map</h2>
      <p class="text-sm text-base-content/70">
        <%= if is_nil(@session.ended_at) do %>
          Operators currently on the net with a known location.
        <% else %>
          Everyone who checked in with a known location.
        <% end %>
      </p>
      <div
        id="net-map"
        phx-hook="LeafletMap"
        phx-update="ignore"
        class="map-canvas"
        data-markers={@net_markers_json}
        data-tile-url={@tile_url}
      >
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def handle_event("check_in", %{"net_checkin" => params} = event_params, socket) do
    params = Map.put(params, "location_ref", event_params["location_ref"])

    case Net.check_in(socket.assigns.session, params) do
      {:ok, _checkin} ->
        {:noreply,
         socket
         |> assign(checkin_form: to_form(Net.change_checkin(%NetCheckin{})))
         |> push_event("checkin_saved", %{})}

      {:error, changeset} ->
        {:noreply, assign(socket, checkin_form: to_form(changeset))}
    end
  end

  def handle_event("edit_name", _params, socket) do
    {:noreply,
     assign(socket,
       editing_name?: true,
       name_form: to_form(%{"name" => socket.assigns.session.name}, as: :net_session)
     )}
  end

  def handle_event("cancel_edit_name", _params, socket) do
    {:noreply, assign(socket, editing_name?: false)}
  end

  def handle_event("rename_session", %{"net_session" => %{"name" => name}}, socket) do
    case Net.rename_session(socket.assigns.session, name) do
      {:ok, session} ->
        {:noreply,
         assign(socket,
           session: %{socket.assigns.session | name: session.name},
           page_title: session.name,
           editing_name?: false
         )}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Net name can't be blank.")}
    end
  end

  def handle_event("edit_aprs_keyword", _params, socket) do
    {:noreply,
     assign(socket,
       editing_aprs_keyword?: true,
       aprs_keyword_form: to_form(Net.change_session(socket.assigns.session))
     )}
  end

  def handle_event("cancel_edit_aprs_keyword", _params, socket) do
    {:noreply, assign(socket, editing_aprs_keyword?: false)}
  end

  def handle_event(
        "update_aprs_keyword",
        %{"net_session" => %{"aprs_keyword" => keyword}},
        socket
      ) do
    case Net.update_aprs_keyword(socket.assigns.session, keyword) do
      {:ok, session} ->
        {:noreply,
         socket |> assign(session: session, editing_aprs_keyword?: false) |> assign_markers()}

      {:error, changeset} ->
        {:noreply, assign(socket, aprs_keyword_form: to_form(changeset))}
    end
  end

  def handle_event("edit_checkin", %{"id" => id}, socket) do
    checkin = find_checkin(socket, id)

    {:noreply,
     assign(socket,
       editing_checkin: checkin,
       edit_checkin_form: to_form(Net.change_checkin(checkin))
     )}
  end

  def handle_event("cancel_edit_checkin", _params, socket) do
    {:noreply, assign(socket, editing_checkin: nil, edit_checkin_form: nil)}
  end

  def handle_event("update_checkin", %{"net_checkin" => params} = event_params, socket) do
    params = Map.put(params, "location_ref", event_params["location_ref"])

    case Net.update_checkin(socket.assigns.session, socket.assigns.editing_checkin, params) do
      {:ok, _checkin} ->
        {:noreply, assign(socket, editing_checkin: nil, edit_checkin_form: nil)}

      {:error, changeset} ->
        {:noreply, assign(socket, edit_checkin_form: to_form(changeset))}
    end
  end

  def handle_event("take_net_control", _params, socket) do
    case socket.assigns.current_scope.member do
      %Member{} = member -> assign_net_control(socket, member)
      _ -> {:noreply, put_flash(socket, :error, "Only approved members may take net control.")}
    end
  end

  def handle_event("open_ncs_modal", _params, socket) do
    {:noreply, assign(socket, ncs_modal?: true, ncs_query: "", ncs_results: nil)}
  end

  def handle_event("close_ncs_modal", _params, socket) do
    {:noreply, assign(socket, ncs_modal?: false, ncs_results: nil)}
  end

  def handle_event("search_ncs", %{"call_sign" => query}, socket) do
    {:noreply,
     assign(socket, ncs_results: Members.search_members_by_call_sign(query), ncs_query: query)}
  end

  def handle_event("assign_net_control", %{"member-id" => member_id}, socket) do
    assign_net_control(socket, Members.get_member!(member_id))
  end

  def handle_event("vacate_net_control", _params, socket) do
    {:ok, session} = Net.vacate_net_control(socket.assigns.session)
    {:noreply, socket |> assign(session: session) |> assign_markers()}
  end

  def handle_event("edit_operation", _params, socket) do
    {:noreply, assign(socket, editing_operation?: true)}
  end

  def handle_event("cancel_edit_operation", _params, socket) do
    {:noreply, assign(socket, editing_operation?: false)}
  end

  def handle_event("assign_operation", %{"operation_id" => operation_id}, socket) do
    operation_id =
      case operation_id do
        "" -> nil
        id -> String.to_integer(id)
      end

    {:ok, session} = Net.assign_operation(socket.assigns.session, operation_id)
    {:noreply, socket |> assign(session: session, editing_operation?: false) |> assign_markers()}
  end

  def handle_event("check_out", %{"id" => id}, socket) do
    case find_checkin(socket, id) do
      %NetCheckin{ended_at: nil} = checkin ->
        {:ok, _checkin} = Net.check_out(checkin)
        {:noreply, socket}

      _already_ended ->
        {:noreply, socket}
    end
  end

  def handle_event("end_session", _params, socket) do
    {:ok, session} = Net.end_session(socket.assigns.session)
    # Reload for the ended check-ins; other viewers refresh via :session_ended.
    {:noreply, socket |> assign(session: Net.get_session!(session.id)) |> assign_markers()}
  end

  @impl true
  def handle_info({:checkin_added, checkin}, socket) do
    session = socket.assigns.session

    {:noreply,
     socket
     |> assign(session: %{session | checkins: session.checkins ++ [checkin]})
     |> assign_markers()}
  end

  def handle_info({:checkin_updated, checkin}, socket) do
    session = socket.assigns.session

    checkins =
      Enum.map(session.checkins, fn c -> if c.id == checkin.id, do: checkin, else: c end)

    {:noreply, socket |> assign(session: %{session | checkins: checkins}) |> assign_markers()}
  end

  def handle_info({:session_ended, _session}, socket) do
    {:noreply,
     socket
     |> assign(
       session: Net.get_session!(socket.assigns.session.id),
       editing_checkin: nil,
       edit_checkin_form: nil
     )
     |> assign_markers()}
  end

  def handle_info({:session_updated, session}, socket) do
    {:noreply,
     socket
     |> assign(session: session, editing_operation?: false)
     |> assign_markers()}
  end

  def handle_info({:session_renamed, renamed}, socket) do
    session = socket.assigns.session
    {:noreply, assign(socket, session: %{session | name: renamed.name}, page_title: renamed.name)}
  end

  defp net_control?(%{member: %Member{id: id}}, session) do
    session.net_control_member_id == id
  end

  defp net_control?(_scope, _session), do: false

  defp assign_net_control(socket, member) do
    case Net.assign_net_control(socket.assigns.session, member) do
      {:ok, session} ->
        {:noreply,
         socket
         |> assign(session: session, ncs_modal?: false, ncs_results: nil)
         |> assign_markers()}

      {:error, :not_approved} ->
        {:noreply,
         socket
         |> put_flash(:error, "Only approved members may be net control.")
         |> assign(ncs_modal?: false, ncs_results: nil)}
    end
  end

  # While the net is live the map tracks who is on frequency right now; once
  # it ends, the map becomes the record of everyone who checked in.
  defp assign_markers(socket) do
    session = socket.assigns.session

    checkins =
      if is_nil(session.ended_at) do
        Enum.filter(session.checkins, &is_nil(&1.ended_at))
      else
        session.checkins
      end

    markers =
      checkins
      |> Enum.uniq_by(&{&1.call_sign, &1.location_point && &1.location_point.coordinates})
      |> Enum.map(fn c -> %{point: c.location_point, title: marker_title(c)} end)

    assign(socket, net_markers_json: MapHelpers.markers_json(markers))
  end

  defp marker_title(checkin) do
    case checkin.location_name do
      nil -> checkin.call_sign
      name -> "#{checkin.call_sign} — #{name}"
    end
  end

  defp location_options(session, default_locations) do
    [{"QTH (member profile)", ""}] ++
      default_location_options(default_locations) ++ operation_location_options(session)
  end

  defp edit_location_options(session, default_locations, checkin) do
    [
      {"Keep current (#{checkin.location_name || "none"})", ""},
      {"QTH (member profile)", "qth"},
      {"None", "none"}
    ] ++
      default_location_options(default_locations) ++ operation_location_options(session)
  end

  defp default_location_options(default_locations) do
    Enum.map(default_locations, &{&1.name, "default:#{&1.id}"})
  end

  defp operation_location_options(%{operation: %{locations: locations} = operation}) do
    Enum.map(locations, &{"#{operation.title}: #{&1.name}", "op:#{&1.id}"})
  end

  defp operation_location_options(_session), do: []

  defp operation_option_label(operation) do
    "#{operation.title} — #{Calendar.strftime(operation.starts_at, "%Y-%m-%d")}"
  end

  defp find_checkin(socket, id) do
    id = String.to_integer(id)
    Enum.find(socket.assigns.session.checkins, fn c -> c.id == id end)
  end

  defp format_duration(checkin) do
    case NetCheckin.duration_seconds(checkin) do
      nil -> "—"
      seconds -> format_seconds(seconds)
    end
  end

  defp format_seconds(seconds) when seconds >= 3600 do
    "#{div(seconds, 3600)}h #{seconds |> rem(3600) |> div(60)}m"
  end

  defp format_seconds(seconds), do: "#{div(seconds, 60)}m #{rem(seconds, 60)}s"
end
