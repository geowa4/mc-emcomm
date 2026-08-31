defmodule McEmcommWeb.NetLive.Show do
  use McEmcommWeb, :live_view

  alias McEmcomm.Net
  alias McEmcomm.Net.NetCheckin

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    session = Net.get_session!(id)

    if connected?(socket), do: Net.subscribe(session.id)

    {:ok,
     assign(socket,
       page_title: session.name || "Net ##{session.id}",
       session: session,
       editing_name?: false,
       name_form: to_form(%{"name" => session.name}, as: :net_session),
       checkin_form: to_form(Net.change_checkin(%NetCheckin{})),
       editing_checkin: nil,
       edit_checkin_form: nil
     )}
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

      <.form
        :if={is_nil(@session.ended_at)}
        for={@checkin_form}
        id="checkin-form"
        phx-submit="check_in"
        class="flex gap-2 items-end flex-wrap mt-4"
      >
        <.input field={@checkin_form[:call_sign]} label="Call sign" required />
        <.input
          field={@checkin_form[:quadrant]}
          type="select"
          label="Quadrant"
          prompt="Auto/none"
          options={["NE", "NW", "SE", "SW", "out_of_county"]}
        />
        <.input field={@checkin_form[:notes]} label="Notes" />
        <.button class="btn btn-primary mb-3">Check in</.button>
      </.form>

      <h2 class="text-lg font-semibold mt-8">Roster</h2>

      <.form
        :if={@editing_checkin}
        for={@edit_checkin_form}
        id="edit-checkin-form"
        phx-submit="update_checkin"
        class="flex gap-2 items-end flex-wrap my-4"
      >
        <.input
          field={@edit_checkin_form[:call_sign]}
          id="edit-checkin-call-sign"
          label="Call sign"
          required
        />
        <.input
          field={@edit_checkin_form[:quadrant]}
          id="edit-checkin-quadrant"
          type="select"
          label="Quadrant"
          prompt="Auto/none"
          options={["NE", "NW", "SE", "SW", "out_of_county"]}
        />
        <.input field={@edit_checkin_form[:notes]} id="edit-checkin-notes" label="Notes" />
        <.button class="btn btn-primary">Save</.button>
        <button type="button" phx-click="cancel_edit_checkin" class="btn btn-ghost">
          Cancel
        </button>
      </.form>

      <.table id="checkins" rows={@session.checkins} row_id={&"checkin-row-#{&1.id}"}>
        <:col :let={c} label="Call sign">{c.call_sign}</:col>
        <:col :let={c} label="Member">{c.member && c.member.name}</:col>
        <:col :let={c} label="Quadrant">{c.quadrant}</:col>
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
    </Layouts.app>
    """
  end

  @impl true
  def handle_event("check_in", %{"net_checkin" => params}, socket) do
    case Net.check_in(socket.assigns.session, params) do
      {:ok, _checkin} ->
        {:noreply, assign(socket, checkin_form: to_form(Net.change_checkin(%NetCheckin{})))}

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

  def handle_event("update_checkin", %{"net_checkin" => params}, socket) do
    case Net.update_checkin(socket.assigns.editing_checkin, params) do
      {:ok, _checkin} ->
        {:noreply, assign(socket, editing_checkin: nil, edit_checkin_form: nil)}

      {:error, changeset} ->
        {:noreply, assign(socket, edit_checkin_form: to_form(changeset))}
    end
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
    {:noreply, assign(socket, session: Net.get_session!(session.id))}
  end

  @impl true
  def handle_info({:checkin_added, checkin}, socket) do
    session = socket.assigns.session
    {:noreply, assign(socket, session: %{session | checkins: session.checkins ++ [checkin]})}
  end

  def handle_info({:checkin_updated, checkin}, socket) do
    session = socket.assigns.session

    checkins =
      Enum.map(session.checkins, fn c -> if c.id == checkin.id, do: checkin, else: c end)

    {:noreply, assign(socket, session: %{session | checkins: checkins})}
  end

  def handle_info({:session_ended, _session}, socket) do
    {:noreply,
     assign(socket,
       session: Net.get_session!(socket.assigns.session.id),
       editing_checkin: nil,
       edit_checkin_form: nil
     )}
  end

  def handle_info({:session_renamed, renamed}, socket) do
    session = socket.assigns.session
    {:noreply, assign(socket, session: %{session | name: renamed.name}, page_title: renamed.name)}
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
