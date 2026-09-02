defmodule McEmcommWeb.NetLive.Console do
  @moduledoc "Net console: any approved member starts a session and takes live check-ins, broadcast via PubSub (§9, §14)."

  use McEmcommWeb, :live_view

  alias McEmcomm.Net
  alias McEmcomm.Operations

  @impl true
  def mount(_params, _session, socket) do
    tz_offset = client_tz_offset(socket)

    {:ok,
     assign(socket,
       page_title: "Net Console",
       sessions: Net.list_sessions() |> Enum.filter(&is_nil(&1.ended_at)),
       past_sessions: Net.list_past_sessions(),
       operations: Operations.list_operations(),
       tz_offset: tz_offset,
       start_form:
         to_form(
           %{"name" => default_net_name(tz_offset), "aprs_keyword" => "", "operation_id" => nil},
           as: :net_session
         )
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>Net Console</.header>

      <.form
        for={@start_form}
        id="start-net-form"
        phx-submit="start_session"
        class="flex gap-2 items-end flex-wrap mt-4"
      >
        <.input field={@start_form[:name]} label="Net name" />
        <.input
          field={@start_form[:aprs_keyword]}
          id="start-net-aprs-keyword"
          label="APRS keyword"
          placeholder="e.g. MCNET"
          required
        />
        <.input
          field={@start_form[:operation_id]}
          id="start-net-operation"
          type="select"
          label="Operation"
          prompt="No operation"
          options={Enum.map(@operations, &{operation_option_label(&1), &1.id})}
        />
        <.button class="btn btn-primary mb-3">Start new net</.button>
      </.form>

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
  def handle_event("start_session", %{"net_session" => params}, socket) do
    name =
      case String.trim(params["name"] || "") do
        "" -> default_net_name(socket.assigns.tz_offset)
        name -> name
      end

    case socket.assigns.current_scope.member do
      %McEmcomm.Members.Member{status: :approved} = member ->
        attrs = %{
          "name" => name,
          "aprs_keyword" => params["aprs_keyword"],
          "operation_id" => params["operation_id"]
        }

        case Net.start_session(member, attrs) do
          {:ok, session} ->
            {:noreply, push_navigate(socket, to: ~p"/app/net/#{session.id}")}

          {:error, %Ecto.Changeset{} = changeset} ->
            {:noreply, assign(socket, start_form: to_form(changeset))}
        end

      _ ->
        {:noreply, put_flash(socket, :error, "Only approved members may start a net.")}
    end
  end

  # Minutes east of UTC, reported by the browser at socket connect so the
  # default name reflects the operator's local date, not UTC's.
  defp client_tz_offset(socket) do
    case get_connect_params(socket) do
      %{"tz_offset_minutes" => offset} when is_integer(offset) and offset in -840..840 -> offset
      _ -> 0
    end
  end

  defp operation_option_label(operation) do
    "#{operation.title} — #{Calendar.strftime(operation.starts_at, "%Y-%m-%d")}"
  end

  defp default_net_name(tz_offset) do
    DateTime.utc_now()
    |> DateTime.add(tz_offset, :minute)
    |> DateTime.to_date()
    |> Date.to_string()
  end
end
