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

  import Phoenix.Controller, only: [put_flash: 3, redirect: 2]
  import Plug.Conn, only: [halt: 1]

  alias McEmcomm.Accounts.Scope

  @doc """
  Plug for non-LiveView routes that require an administrator.

  Used for LiveDashboard, which exposes process state, ETS contents, and the
  application environment (which in production holds the Resend API key, the
  webhook secret, and the database URL). Registration is open to the public,
  so authentication alone is not a sufficient gate there.

  Runs after `McEmcommWeb.UserAuth.fetch_current_scope_for_user/2`, which the
  `:browser` pipeline already includes.
  """
  @spec require_admin_user(Plug.Conn.t(), keyword()) :: Plug.Conn.t()
  def require_admin_user(conn, _opts) do
    if Scope.admin?(conn.assigns[:current_scope]) do
      conn
    else
      conn
      |> put_flash(:error, "You must be an administrator to access this page.")
      |> redirect(to: ~p"/")
      |> halt()
    end
  end

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
