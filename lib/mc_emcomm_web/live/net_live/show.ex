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
       checkin_form: to_form(Net.change_checkin(%NetCheckin{}))
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
            class="flex gap-2 items-center"
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
        <.button class="btn btn-primary">Check in</.button>
      </.form>

      <h2 class="text-lg font-semibold mt-8">Roster</h2>
      <.table id="checkins" rows={@session.checkins}>
        <:col :let={c} label="Call sign">{c.call_sign}</:col>
        <:col :let={c} label="Member">{c.member && c.member.name}</:col>
        <:col :let={c} label="Quadrant">{c.quadrant}</:col>
        <:col :let={c} label="Notes">{c.notes}</:col>
        <:col :let={c} label="Time">{Calendar.strftime(c.recorded_at, "%H:%M:%S")}</:col>
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

  def handle_event("end_session", _params, socket) do
    {:ok, session} = Net.end_session(socket.assigns.session)
    {:noreply, assign(socket, session: %{socket.assigns.session | ended_at: session.ended_at})}
  end

  @impl true
  def handle_info({:checkin_added, checkin}, socket) do
    session = socket.assigns.session
    {:noreply, assign(socket, session: %{session | checkins: session.checkins ++ [checkin]})}
  end

  def handle_info({:session_renamed, renamed}, socket) do
    session = socket.assigns.session
    {:noreply, assign(socket, session: %{session | name: renamed.name}, page_title: renamed.name)}
  end
end
