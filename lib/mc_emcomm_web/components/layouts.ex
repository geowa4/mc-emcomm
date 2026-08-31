defmodule McEmcommWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use McEmcommWeb, :html

  alias McEmcomm.Accounts.Scope

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates "layouts/*"

  @doc """
  Renders your app layout.

  This function is typically invoked from every template,
  and it often contains your application menu, sidebar,
  or similar.

  ## Examples

      <Layouts.app flash={@flash}>
        <h1>Content</h1>
      </Layouts.app>

  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://phoenix.hexdocs.pm/scopes.html)"

  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <header class="navbar px-4 sm:px-6 lg:px-8">
      <div class="flex-1">
        <a href="/" class="flex-1 flex w-fit items-center gap-2">
          <img src={~p"/images/logo.svg"} width="36" />
          <span class="text-sm font-semibold">Monroe County ARES/RACES</span>
        </a>
      </div>
      <div class="flex-none">
        <ul class="hidden lg:flex px-1 space-x-2 xl:space-x-4 items-center text-sm">
          <li><a href={~p"/about"} class="btn btn-ghost btn-sm">About</a></li>
          <li><a href={~p"/training"} class="btn btn-ghost btn-sm">Training</a></li>
          <li><a href={~p"/resources"} class="btn btn-ghost btn-sm">Resources</a></li>
          <li><a href={~p"/exercises"} class="btn btn-ghost btn-sm">Exercises</a></li>
          <li><a href={~p"/calendar"} class="btn btn-ghost btn-sm">Calendar</a></li>
          <li :if={@current_scope}>
            <a href={~p"/app"} class="btn btn-ghost btn-sm">Member Portal</a>
          </li>
          <li :if={@current_scope && @current_scope.user && @current_scope.user.is_admin}>
            <a href={~p"/admin"} class="btn btn-ghost btn-sm">Admin</a>
          </li>
          <li>
            <.theme_toggle />
          </li>
          <li :if={@current_scope && @current_scope.user}>
            <div class="dropdown dropdown-end">
              <button id="user-menu" tabindex="0" class="btn btn-ghost btn-sm">
                {display_name(@current_scope)}
                <.icon name="hero-chevron-down-micro" class="size-4" />
              </button>
              <ul
                tabindex="0"
                class="dropdown-content menu bg-base-100 rounded-box z-20 mt-1 w-40 p-2 shadow"
              >
                <li :if={Scope.approved_member?(@current_scope)}>
                  <.link id="user-menu-profile" href={~p"/app/profile"}>My Profile</.link>
                </li>
                <li>
                  <.link id="user-menu-settings" href={~p"/users/settings"}>Account</.link>
                </li>
                <li>
                  <.link id="user-menu-log-out" href={~p"/users/log-out"} method="delete">
                    Log out
                  </.link>
                </li>
              </ul>
            </div>
          </li>
          <li :if={!(@current_scope && @current_scope.user)}>
            <a href={~p"/users/register"} class="btn btn-ghost btn-sm">Register</a>
          </li>
          <li :if={!(@current_scope && @current_scope.user)}>
            <a href={~p"/users/log-in"} class="btn btn-primary btn-sm">Log in</a>
          </li>
        </ul>
        <div class="dropdown dropdown-end lg:hidden">
          <button id="mobile-menu" tabindex="0" class="btn btn-ghost btn-square" aria-label="Menu">
            <.icon name="hero-bars-3" class="size-6" />
          </button>
          <ul
            tabindex="0"
            class="dropdown-content menu bg-base-100 rounded-box z-20 mt-1 w-52 p-2 shadow"
          >
            <li><a href={~p"/about"}>About</a></li>
            <li><a href={~p"/training"}>Training</a></li>
            <li><a href={~p"/resources"}>Resources</a></li>
            <li><a href={~p"/exercises"}>Exercises</a></li>
            <li><a href={~p"/calendar"}>Calendar</a></li>
            <li :if={@current_scope}>
              <a href={~p"/app"}>Member Portal</a>
            </li>
            <li :if={@current_scope && @current_scope.user && @current_scope.user.is_admin}>
              <a href={~p"/admin"}>Admin</a>
            </li>
            <li class="divider my-1" aria-hidden="true"></li>
            <li :if={Scope.approved_member?(@current_scope)}>
              <.link id="mobile-menu-profile" href={~p"/app/profile"}>My Profile</.link>
            </li>
            <li :if={@current_scope && @current_scope.user}>
              <.link id="mobile-menu-settings" href={~p"/users/settings"}>Account</.link>
            </li>
            <li :if={@current_scope && @current_scope.user}>
              <.link id="mobile-menu-log-out" href={~p"/users/log-out"} method="delete">
                Log out
              </.link>
            </li>
            <li :if={!(@current_scope && @current_scope.user)}>
              <a href={~p"/users/register"}>Register</a>
            </li>
            <li :if={!(@current_scope && @current_scope.user)}>
              <a href={~p"/users/log-in"}>Log in</a>
            </li>
            <li class="divider my-1" aria-hidden="true"></li>
            <li class="p-1">
              <.theme_toggle />
            </li>
          </ul>
        </div>
      </div>
    </header>

    <main class="px-4 py-12 sm:px-6 lg:px-8">
      <div class="mx-auto max-w-4xl space-y-4">
        {render_slot(@inner_block)}
      </div>
    </main>

    <footer id="site-footer" class="px-4 py-8 sm:px-6 lg:px-8 border-t border-base-300">
      <div class="mx-auto max-w-4xl text-center space-y-3 text-sm text-base-content/70">
        <ul class="flex flex-wrap justify-center gap-x-6 gap-y-2">
          <li>
            <a class="link link-hover" href="mailto:webmaster@monroecountyemcomm.org">Email Us</a>
          </li>
          <li>
            <a
              class="link link-hover"
              href="https://www.facebook.com/MCARESNY"
              target="_blank"
              rel="noopener"
            >
              Facebook
            </a>
          </li>
          <li>
            <a class="link link-hover" href="https://x.com/MCARESNY" target="_blank" rel="noopener">
              X
            </a>
          </li>
          <li>
            <a
              class="link link-hover"
              href="https://groups.io/g/MonroeCountyEmcomm"
              target="_blank"
              rel="noopener"
            >
              Groups.io
            </a>
          </li>
          <li>
            <a
              class="link link-hover"
              href="https://calendar.google.com/calendar/u/0?cid=Y180N2EzNGE5MDZmMzRiYTI3YzZjYWNkZTdhMTY4YTExMDk1NzE2MDAzNTgxN2I0MDhkMjU1M2I2MjQzNGZjM2Y3QGdyb3VwLmNhbGVuZGFyLmdvb2dsZS5jb20"
              target="_blank"
              rel="noopener"
            >
              Calendar
            </a>
          </li>
        </ul>
        <p>&copy; {Date.utc_today().year} Monroe County ARES/RACES. All rights reserved.</p>
        <p class="italic">When All Else Fails, Amateur Radio</p>
      </div>
    </footer>

    <.flash_group flash={@flash} />
    """
  end

  defp display_name(%{member: %{call_sign: call_sign}}) when is_binary(call_sign), do: call_sign
  defp display_name(%{member: %{name: name}}) when is_binary(name), do: name
  defp display_name(%{user: user}), do: user.email |> String.split("@") |> hd()

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={
          show(".phx-client-error #client-error")
          |> JS.remove_attribute("hidden", to: ".phx-client-error #client-error")
        }
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={
          show(".phx-server-error #server-error")
          |> JS.remove_attribute("hidden", to: ".phx-server-error #server-error")
        }
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end

  @doc """
  Provides dark vs light theme toggle based on themes defined in app.css.

  See <head> in root.html.heex which applies the theme before page load.
  """
  def theme_toggle(assigns) do
    ~H"""
    <div class="card relative flex flex-row items-center border-2 border-base-300 bg-base-300 rounded-full">
      <div class="absolute w-1/3 h-full rounded-full border-1 border-base-200 bg-base-100 brightness-200 left-0 [[data-theme=light]_&]:left-1/3 [[data-theme=dark]_&]:left-2/3 [[data-theme-source=system]_&]:!left-0 transition-[left]" />

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="system"
      >
        <.icon name="hero-computer-desktop-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="light"
      >
        <.icon name="hero-sun-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="dark"
      >
        <.icon name="hero-moon-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>
    </div>
    """
  end
end
