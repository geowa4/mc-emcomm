defmodule McEmcommWeb.ActiveNet do
  @moduledoc """
  Keeps `@active_net` current in every LiveView so the header emblem can show
  when a net is on the air (`McEmcommWeb.Layouts.app/1`).

  Mounted in every `live_session`. It subscribes to `McEmcomm.Net.subscribe_nets/0`
  and re-checks the flag when a net starts or ends; other `{:nets_changed, _}`
  reasons (check-ins, keyword edits) cannot change it and are dropped. The
  hook halts on those messages, so a LiveView that needs them must handle
  them in a hook of its own attached before this one.
  """

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [attach_hook: 4, connected?: 1]

  alias McEmcomm.Net

  def on_mount(:default, _params, _session, socket) do
    if connected?(socket), do: Net.subscribe_nets()

    {:cont,
     socket
     |> assign(:active_net, Net.active_session?())
     |> attach_hook(:active_net, :handle_info, &handle_nets_changed/2)}
  end

  defp handle_nets_changed({:nets_changed, reason}, socket)
       when reason in [:session_started, :session_ended] do
    {:halt, assign(socket, :active_net, Net.active_session?())}
  end

  defp handle_nets_changed({:nets_changed, _reason}, socket), do: {:halt, socket}
  defp handle_nets_changed(_message, socket), do: {:cont, socket}
end
