defmodule McEmcommWeb.MemberAuth do
  @moduledoc """
  LiveView `on_mount` hooks for the `:member` and `:admin` tiers (spec §3).

  Both hooks first mount `current_scope` exactly as
  `McEmcommWeb.UserAuth.on_mount(:require_authenticated, ...)` does, then
  layer on the membership/admin check. Enforcing this in `on_mount` (rather
  than only hiding UI) is what makes `/app/*` and `/admin/*` actually
  unreachable for the wrong tier, not merely unlinked.
  """

  use McEmcommWeb, :verified_routes

  alias McEmcomm.Accounts.Scope

  @doc false
  def on_mount(:require_member, params, session, socket) do
    case McEmcommWeb.UserAuth.on_mount(:require_authenticated, params, session, socket) do
      {:cont, socket} ->
        scope = socket.assigns.current_scope

        if Scope.approved_member?(scope) or Scope.admin?(scope) do
          {:cont, socket}
        else
          {:halt, deny(socket, "You must be an approved member to access this page.")}
        end

      halt ->
        halt
    end
  end

  def on_mount(:require_admin, params, session, socket) do
    case McEmcommWeb.UserAuth.on_mount(:require_authenticated, params, session, socket) do
      {:cont, socket} ->
        if Scope.admin?(socket.assigns.current_scope) do
          {:cont, socket}
        else
          {:halt, deny(socket, "You must be an administrator to access this page.")}
        end

      halt ->
        halt
    end
  end

  defp deny(socket, message) do
    socket
    |> Phoenix.LiveView.put_flash(:error, message)
    |> Phoenix.LiveView.redirect(to: ~p"/")
  end
end
