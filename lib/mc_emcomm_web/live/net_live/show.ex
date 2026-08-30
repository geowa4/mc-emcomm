defmodule McEmcommWeb.NetLive.Show do
  use McEmcommWeb, :live_view

  alias McEmcomm.Accounts.Scope
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
       may_end?: may_end?(socket.assigns.current_scope, session),
       checkin_form: to_form(Net.change_checkin(%NetCheckin{}))
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        {@session.name || "Net ##{@session.id}"}
        <:subtitle>Started {Calendar.strftime(@session.started_at, "%Y-%m-%d %H:%M")}</:subtitle>
        <:actions>
          <.button
            :if={is_nil(@session.ended_at) and @may_end?}
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

  def handle_event("end_session", _params, socket) do
    if socket.assigns.may_end? do
      {:ok, session} = Net.end_session(socket.assigns.session)
      {:noreply, assign(socket, session: %{socket.assigns.session | ended_at: session.ended_at})}
    else
      {:noreply, put_flash(socket, :error, "Only the operator who started this net can end it.")}
    end
  end

  @impl true
  def handle_info({:checkin_added, checkin}, socket) do
    session = socket.assigns.session
    {:noreply, assign(socket, session: %{session | checkins: session.checkins ++ [checkin]})}
  end

  # Every approved member may take check-ins on any net, but closing one out
  # belongs to the operator who started it (or to an admin).
  defp may_end?(scope, session) do
    Scope.admin?(scope) or started_net?(scope, session)
  end

  defp started_net?(%Scope{member: %{id: id}}, %{started_by_member_id: id}), do: true
  defp started_net?(_scope, _session), do: false
end
