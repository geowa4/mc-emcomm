defmodule McEmcommWeb.NetLive.Console do
  @moduledoc "Net console: any approved member starts a session and takes live check-ins, broadcast via PubSub (§9, §14)."

  use McEmcommWeb, :live_view

  alias McEmcomm.Net

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: "Net Console",
       sessions: Net.list_sessions() |> Enum.filter(&is_nil(&1.ended_at)),
       past_sessions: Net.list_past_sessions()
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        Net Console
        <:actions>
          <.button phx-click="start_session" class="btn btn-primary">Start new net</.button>
        </:actions>
      </.header>

      <h2 class="text-lg font-semibold mt-4">Active sessions</h2>
      <ul :if={@sessions != []} class="list bg-base-100 rounded-box border border-base-300">
        <li :for={s <- @sessions} class="list-row">
          <.link navigate={~p"/app/net/#{s.id}"} class="link link-hover font-semibold">
            {s.name || "Net ##{s.id}"} &mdash; started {Calendar.strftime(
              s.started_at,
              "%Y-%m-%d %H:%M"
            )}
          </.link>
        </li>
      </ul>
      <p :if={@sessions == []} class="text-base-content/70">No active net right now.</p>

      <h2 class="text-lg font-semibold mt-8">Past nets</h2>
      <ul :if={@past_sessions != []} class="list bg-base-100 rounded-box border border-base-300">
        <li :for={s <- @past_sessions} class="list-row">
          <.link navigate={~p"/app/net/#{s.id}"} class="link link-hover">
            {s.name || "Net ##{s.id}"} &mdash; {Calendar.strftime(s.started_at, "%Y-%m-%d")}
          </.link>
        </li>
      </ul>
    </Layouts.app>
    """
  end

  @impl true
  def handle_event("start_session", _params, socket) do
    case socket.assigns.current_scope.member do
      %McEmcomm.Members.Member{status: :approved} = member ->
        case Net.start_session(member, %{}) do
          {:ok, session} -> {:noreply, push_navigate(socket, to: ~p"/app/net/#{session.id}")}
          {:error, _} -> {:noreply, put_flash(socket, :error, "Could not start a net session.")}
        end

      _ ->
        {:noreply, put_flash(socket, :error, "Only approved members may start a net.")}
    end
  end
end
