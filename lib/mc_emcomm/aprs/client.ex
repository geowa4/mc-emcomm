defmodule McEmcomm.Aprs.Client do
  @moduledoc """
  The application's single, receive-only APRS-IS connection.

  One connection serves every active net: its server-side filter is a radius
  around each net location plus a budlist term per APRS-tracked station (see
  `McEmcomm.Aprs.Filter`), and every position report that passes is handed to
  `McEmcomm.Net.record_aprs_position/1`, which decides what it means for each
  net. The filter is rebuilt when nets change (`McEmcomm.Net.subscribe_nets/0`,
  debounced) and periodically as a safety net, and is pushed to the open
  connection with a `#filter` line rather than a reconnect. With no active net
  the filter is empty and the client idles disconnected.

  Two app instances overlap during a blue-green deploy and both receive the
  same packets; `record_aprs_position/1` is idempotent for that reason.
  """

  use GenServer

  require Logger

  alias McEmcomm.Aprs.Filter
  alias McEmcomm.Aprs.Packet
  alias McEmcomm.Net

  @refresh_ms :timer.seconds(60)
  @debounce_ms 500
  @connect_timeout_ms :timer.seconds(10)
  @idle_timeout_ms :timer.seconds(120)
  @initial_backoff_ms :timer.seconds(1)
  @max_backoff_ms :timer.seconds(60)

  @doc """
  Options override `config :mc_emcomm, :aprs` (`:host`, `:port`, `:call_sign`,
  `:passcode`, `:radius_km`) and the timers (`:refresh_ms`, `:connect_timeout_ms`,
  `:idle_timeout_ms`); `:name` defaults to the module.
  """
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
  end

  @doc "Connection status and the filter in force, for tests and diagnostics."
  @spec state(GenServer.server()) :: %{
          status: :idle | :connecting | :connected,
          filter: String.t()
        }
  def state(server \\ __MODULE__), do: GenServer.call(server, :state)

  @impl true
  def init(opts) do
    env = Application.fetch_env!(:mc_emcomm, :aprs)

    config = %{
      host: to_charlist(opts[:host] || env[:server]),
      port: opts[:port] || env[:port],
      call_sign: opts[:call_sign] || env[:call_sign],
      passcode: opts[:passcode] || env[:passcode],
      radius_km: opts[:radius_km] || env[:radius_km],
      refresh_ms: opts[:refresh_ms] || @refresh_ms,
      connect_timeout_ms: opts[:connect_timeout_ms] || @connect_timeout_ms,
      idle_timeout_ms: opts[:idle_timeout_ms] || @idle_timeout_ms
    }

    Net.subscribe_nets()
    Process.send_after(self(), :periodic_refresh, config.refresh_ms)

    state = %{
      config: config,
      socket: nil,
      status: :idle,
      filter: "",
      backoff_ms: @initial_backoff_ms,
      refresh_timer: nil,
      idle_timer: nil,
      connect_timer: nil
    }

    {:ok, state, {:continue, :refresh}}
  end

  @impl true
  def handle_continue(:refresh, state), do: {:noreply, refresh(state)}

  @impl true
  def handle_call(:state, _from, state) do
    {:reply, %{status: state.status, filter: state.filter}, state}
  end

  @impl true
  def handle_info(:refresh, state) do
    {:noreply, refresh(%{state | refresh_timer: nil})}
  end

  def handle_info(:periodic_refresh, state) do
    Process.send_after(self(), :periodic_refresh, state.config.refresh_ms)
    {:noreply, refresh(state)}
  end

  # A burst of changes (a net starting and checking in net control, a packet
  # touching several nets) yields one refresh, shortly after the last change.
  def handle_info({:nets_changed, _reason}, state) do
    cancel_timer(state.refresh_timer)
    timer = Process.send_after(self(), :refresh, @debounce_ms)
    {:noreply, %{state | refresh_timer: timer}}
  end

  def handle_info(:connect, state), do: {:noreply, connect(%{state | connect_timer: nil})}

  def handle_info({:tcp, socket, line}, %{socket: socket} = state) do
    handle_line(line)
    :inet.setopts(socket, active: :once)
    {:noreply, reset_idle_timer(state)}
  end

  def handle_info({:tcp_closed, socket}, %{socket: socket} = state) do
    {:noreply, lost(state, "connection closed by server")}
  end

  def handle_info({:tcp_error, socket, reason}, %{socket: socket} = state) do
    {:noreply, lost(state, "socket error #{inspect(reason)}")}
  end

  def handle_info(:idle_timeout, %{socket: socket} = state) when not is_nil(socket) do
    {:noreply, lost(state, "no traffic for #{state.config.idle_timeout_ms}ms")}
  end

  # Messages from a socket we have already closed, or timers for one.
  def handle_info(_message, state), do: {:noreply, state}

  ## Filter refresh

  defp refresh(state) do
    case build_filter(state) do
      {:ok, ""} ->
        if state.status != :idle, do: Logger.info("APRS-IS idle: no active net to listen for")
        state |> close_socket() |> Map.merge(%{status: :idle, filter: ""})

      {:ok, filter} when filter == state.filter ->
        if state.status == :idle, do: connect(state), else: state

      {:ok, filter} ->
        apply_filter(%{state | filter: filter})

      :error ->
        state
    end
  end

  defp apply_filter(%{status: :connected} = state) do
    case :gen_tcp.send(state.socket, Filter.filter_line(state.filter)) do
      :ok ->
        Logger.info("APRS-IS filter updated: #{state.filter}")
        state

      {:error, reason} ->
        lost(state, "send failed #{inspect(reason)}")
    end
  end

  defp apply_filter(%{status: :connecting} = state), do: state
  defp apply_filter(%{status: :idle} = state), do: connect(state)

  # The database is consulted outside init/1 and errors are swallowed so a
  # database blip retries on the next refresh instead of crash-looping the
  # supervisor.
  defp build_filter(state) do
    {points, call_signs} = Net.aprs_filter_inputs()
    {:ok, Filter.build(points, call_signs, state.config.radius_km)}
  rescue
    error ->
      Logger.error("APRS-IS filter rebuild failed: #{Exception.message(error)}")
      :error
  catch
    :exit, reason ->
      Logger.error("APRS-IS filter rebuild failed: #{inspect(reason)}")
      :error
  end

  ## Connection lifecycle

  defp connect(%{filter: ""} = state), do: %{state | status: :idle}

  defp connect(state) do
    %{host: host, port: port, call_sign: call_sign, passcode: passcode} = state.config
    login = Filter.login_line(call_sign, passcode, version(), state.filter)
    socket_opts = [:binary, packet: :line, active: :once, keepalive: true, send_timeout: 5_000]

    with {:ok, socket} <-
           :gen_tcp.connect(host, port, socket_opts, state.config.connect_timeout_ms),
         :ok <- send_or_close(socket, login) do
      Logger.info("APRS-IS connected to #{host}:#{port} as #{call_sign}; filter #{state.filter}")

      reset_idle_timer(%{
        state
        | socket: socket,
          status: :connected,
          backoff_ms: @initial_backoff_ms
      })
    else
      {:error, reason} ->
        Logger.warning(
          "APRS-IS connection to #{host}:#{port} failed: #{inspect(reason)}; " <>
            "retrying in #{state.backoff_ms}ms"
        )

        schedule_connect(state)
    end
  end

  defp send_or_close(socket, data) do
    case :gen_tcp.send(socket, data) do
      :ok ->
        :ok

      {:error, _reason} = error ->
        :gen_tcp.close(socket)
        error
    end
  end

  defp lost(state, why) do
    Logger.warning("APRS-IS #{why}; reconnecting in #{state.backoff_ms}ms")
    state |> close_socket() |> schedule_connect()
  end

  defp schedule_connect(state) do
    timer = Process.send_after(self(), :connect, state.backoff_ms)

    %{
      state
      | status: :connecting,
        connect_timer: timer,
        backoff_ms: min(state.backoff_ms * 2, @max_backoff_ms)
    }
  end

  defp close_socket(state) do
    if state.socket, do: :gen_tcp.close(state.socket)
    cancel_timer(state.idle_timer)
    cancel_timer(state.connect_timer)
    %{state | socket: nil, idle_timer: nil, connect_timer: nil}
  end

  defp reset_idle_timer(state) do
    cancel_timer(state.idle_timer)
    timer = Process.send_after(self(), :idle_timeout, state.config.idle_timeout_ms)
    %{state | idle_timer: timer}
  end

  defp cancel_timer(nil), do: :ok
  defp cancel_timer(timer), do: Process.cancel_timer(timer)

  ## Inbound lines

  defp handle_line("# logresp" <> _ = line), do: Logger.info("APRS-IS #{String.trim(line)}")
  defp handle_line("#" <> _ = line), do: Logger.debug("APRS-IS #{String.trim(line)}")

  defp handle_line(line) do
    case Packet.position_report(line) do
      {:ok, position} -> Net.record_aprs_position(position)
      :error -> :ok
    end
  rescue
    error ->
      Logger.error("APRS-IS packet handling failed: #{Exception.message(error)}")
  catch
    :exit, reason ->
      Logger.error("APRS-IS packet handling failed: #{inspect(reason)}")
  end

  defp version, do: :mc_emcomm |> Application.spec(:vsn) |> to_string()
end
