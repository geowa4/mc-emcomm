defmodule McEmcommWeb.UserLive.TwoFactor do
  @moduledoc """
  Settings page for enrolling in, and turning off, TOTP two-factor
  authentication.

  During enrollment the unconfirmed secret lives only in this process's
  assigns; nothing touches the database until the user proves they scanned
  it by entering a valid code. Reloading the page simply starts over with a
  fresh secret.
  """
  use McEmcommWeb, :live_view

  on_mount {McEmcommWeb.UserAuth, :require_sudo_mode}

  alias McEmcomm.Accounts
  alias McEmcomm.Accounts.RecoveryCode

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="text-center">
        <.header>
          Two-factor authentication
          <:subtitle>
            Protect your account with a code from an authenticator app in addition to your password
            or magic link.
          </:subtitle>
        </.header>
      </div>

      <p class="text-center">
        Status:
        <span
          id="two-factor-status"
          class={["badge", if(@enabled?, do: "badge-success", else: "badge-neutral")]}
        >
          {if @enabled?, do: "On", else: "Off"}
        </span>
      </p>

      <section :if={@recovery_codes} id="two-factor-recovery-codes" class="space-y-4">
        <div class="alert alert-warning">
          <.icon name="hero-exclamation-triangle" class="size-6 shrink-0" />
          <div>
            <p class="font-semibold">Save these recovery codes now.</p>
            <p>
              Each one logs you in once if you lose your authenticator. They will not be shown again.
            </p>
          </div>
        </div>
        <ul class="grid grid-cols-2 gap-2 font-mono text-center">
          <li :for={{code, index} <- Enum.with_index(@recovery_codes)} id={"recovery-code-#{index}"}>
            <code>{code}</code>
          </li>
        </ul>
        <.button
          id="two-factor-recovery-codes-done"
          variant="primary"
          phx-click="dismiss_recovery_codes"
        >
          I have saved these codes
        </.button>
      </section>

      <%= cond do %>
        <% @enabled? -> %>
          <section id="two-factor-enabled" class="space-y-4">
            <p id="two-factor-recovery-count">
              {@unused_recovery_count} of {RecoveryCode.code_count()} recovery codes remaining.
            </p>
            <div class="flex flex-wrap gap-2">
              <.button
                id="two-factor-regenerate"
                phx-click="regenerate_recovery_codes"
                data-confirm="Generate new recovery codes? Your existing codes will stop working."
              >
                Generate new recovery codes
              </.button>
              <.button
                id="two-factor-disable"
                class="btn btn-error btn-soft"
                phx-click="disable"
                data-confirm="Turn off two-factor authentication? You will only need your password or a magic link to log in."
              >
                Turn off two-factor authentication
              </.button>
            </div>
          </section>
        <% @secret -> %>
          <section id="two-factor-enrolling" class="space-y-4">
            <ol class="list-decimal space-y-2 pl-6">
              <li>Open your authenticator app and scan this QR code.</li>
              <li>Enter the six-digit code it shows to finish.</li>
            </ol>
            <figure id="two-factor-qr" class="mx-auto w-fit rounded bg-white p-2">
              {raw(@qr_svg)}
            </figure>
            <p class="text-center text-sm">
              Can't scan? Enter this key manually:
              <code id="two-factor-secret" class="break-all">{@manual_key}</code>
            </p>
            <.form for={@confirm_form} id="two_factor_confirm_form" phx-submit="confirm_enrollment">
              <.input
                field={@confirm_form[:code]}
                type="text"
                label="Code from your app"
                autocomplete="one-time-code"
                inputmode="numeric"
                pattern="[0-9]{6}"
                maxlength="6"
                spellcheck="false"
                required
                phx-mounted={JS.focus()}
              />
              <div class="flex gap-2">
                <.button variant="primary" phx-disable-with="Verifying...">Turn on</.button>
                <button
                  id="two-factor-cancel"
                  type="button"
                  class="btn"
                  phx-click="cancel_enrollment"
                >
                  Cancel
                </button>
              </div>
            </.form>
          </section>
        <% true -> %>
          <section id="two-factor-disabled" class="space-y-4">
            <p>
              You will need an authenticator app such as Google Authenticator, Authy, or 1Password.
              After you turn this on, every login asks for a six-digit code from the app.
            </p>
            <.button id="two-factor-begin" variant="primary" phx-click="begin_enrollment">
              Set up authenticator app
            </.button>
          </section>
      <% end %>

      <p>
        <.link id="two-factor-back" navigate={~p"/users/settings"} class="link">
          Back to account
        </.link>
      </p>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_scope.user

    {:ok,
     socket
     |> assign(:page_title, "Two-factor authentication")
     |> assign(:enabled?, Accounts.totp_enabled?(user))
     |> assign(:unused_recovery_count, Accounts.count_unused_recovery_codes(user))
     |> assign(:recovery_codes, nil)
     |> clear_enrollment()}
  end

  @impl true
  def handle_event("begin_enrollment", _params, socket) do
    user = socket.assigns.current_scope.user
    secret = Accounts.generate_totp_secret()
    uri = Accounts.totp_provisioning_uri(user, secret)

    {:noreply,
     socket
     |> assign(:secret, secret)
     |> assign(:manual_key, Base.encode32(secret, padding: false))
     |> assign(:qr_svg, qr_svg(uri))
     |> assign(:confirm_form, blank_confirm_form())}
  end

  def handle_event("cancel_enrollment", _params, socket) do
    {:noreply, clear_enrollment(socket)}
  end

  def handle_event("confirm_enrollment", %{"totp" => %{"code" => code}}, socket) do
    user = socket.assigns.current_scope.user
    true = Accounts.sudo_mode?(user)

    case Accounts.enable_totp(user, socket.assigns.secret, String.trim(code)) do
      {:ok, {user, recovery_codes}} ->
        {:noreply,
         socket
         |> put_user(user)
         |> assign(:enabled?, true)
         |> assign(:recovery_codes, recovery_codes)
         |> assign(:unused_recovery_count, length(recovery_codes))
         |> clear_enrollment()
         |> put_flash(:info, "Two-factor authentication is on.")}

      {:error, :invalid_code} ->
        form = to_form(%{"code" => code}, as: "totp", errors: [code: {"is not valid", []}])
        {:noreply, assign(socket, :confirm_form, form)}
    end
  end

  def handle_event("regenerate_recovery_codes", _params, socket) do
    user = socket.assigns.current_scope.user
    true = Accounts.sudo_mode?(user)
    {:ok, recovery_codes} = Accounts.regenerate_recovery_codes(user)

    {:noreply,
     socket
     |> assign(:recovery_codes, recovery_codes)
     |> assign(:unused_recovery_count, length(recovery_codes))
     |> put_flash(:info, "New recovery codes generated. Your old codes no longer work.")}
  end

  def handle_event("disable", _params, socket) do
    user = socket.assigns.current_scope.user
    true = Accounts.sudo_mode?(user)
    {:ok, user} = Accounts.disable_totp(user)

    {:noreply,
     socket
     |> put_user(user)
     |> assign(:enabled?, false)
     |> assign(:recovery_codes, nil)
     |> assign(:unused_recovery_count, 0)
     |> clear_enrollment()
     |> put_flash(:info, "Two-factor authentication is off.")}
  end

  def handle_event("dismiss_recovery_codes", _params, socket) do
    {:noreply, assign(socket, :recovery_codes, nil)}
  end

  defp clear_enrollment(socket) do
    socket
    |> assign(:secret, nil)
    |> assign(:manual_key, nil)
    |> assign(:qr_svg, nil)
    |> assign(:confirm_form, blank_confirm_form())
  end

  defp blank_confirm_form, do: to_form(%{"code" => ""}, as: "totp")

  # Keep the virtual authenticated_at so sudo mode survives the update.
  defp put_user(socket, user) do
    scope = socket.assigns.current_scope
    user = %{user | authenticated_at: scope.user.authenticated_at}
    assign(socket, :current_scope, %{scope | user: user})
  end

  defp qr_svg(uri) do
    uri |> EQRCode.encode() |> EQRCode.svg(width: 240)
  end
end
