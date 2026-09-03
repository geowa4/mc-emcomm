defmodule McEmcommWeb.UserLive.TwoFactorChallenge do
  @moduledoc """
  Second step of login for users with TOTP enabled.

  The page only collects the code. Verification and session creation happen
  in `McEmcommWeb.UserSessionController.verify_two_factor/2`, reached through
  `phx-trigger-action`, because a LiveView cannot set cookies.
  """
  use McEmcommWeb, :live_view

  alias McEmcommWeb.UserAuth

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="mx-auto max-w-sm space-y-4">
        <div class="text-center">
          <.header>
            Two-factor authentication
            <:subtitle>
              <%= if @mode == :totp do %>
                Enter the six-digit code from your authenticator app.
              <% else %>
                Enter one of the recovery codes you saved when you set up two-factor authentication.
              <% end %>
            </:subtitle>
          </.header>
        </div>

        <.form
          for={@form}
          id="two_factor_form"
          action={~p"/users/two-factor"}
          method="post"
          phx-submit="submit"
          phx-trigger-action={@trigger_submit}
        >
          <%= if @mode == :totp do %>
            <.input
              field={@form[:code]}
              type="text"
              label="Authenticator code"
              autocomplete="one-time-code"
              inputmode="numeric"
              pattern="[0-9]{6}"
              maxlength="6"
              spellcheck="false"
              required
              phx-mounted={JS.focus()}
            />
          <% else %>
            <.input
              field={@form[:code]}
              type="text"
              label="Recovery code"
              autocomplete="off"
              maxlength="19"
              spellcheck="false"
              required
              phx-mounted={JS.focus()}
            />
          <% end %>
          <.button class="btn btn-primary w-full" phx-disable-with="Verifying...">
            Verify
          </.button>
        </.form>

        <p class="text-center text-sm">
          <%= if @mode == :totp do %>
            <.link id="two-factor-use-recovery" phx-click="use_recovery" class="link">
              Use a recovery code instead
            </.link>
          <% else %>
            <.link id="two-factor-use-totp" phx-click="use_totp" class="link">
              Use your authenticator app instead
            </.link>
          <% end %>
        </p>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, session, socket) do
    if UserAuth.valid_pending_two_factor(session["pending_two_factor"]) do
      {:ok,
       socket
       |> assign(:page_title, "Two-factor authentication")
       |> assign(:mode, :totp)
       |> assign(:trigger_submit, false)
       |> assign_blank_form()}
    else
      {:ok,
       socket
       |> put_flash(:error, "Your login has expired. Please log in again.")
       |> push_navigate(to: ~p"/users/log-in")}
    end
  end

  @impl true
  def handle_event("submit", %{"user" => params}, socket) do
    {:noreply, assign(socket, form: to_form(params, as: "user"), trigger_submit: true)}
  end

  def handle_event("use_recovery", _params, socket) do
    {:noreply, socket |> assign(:mode, :recovery) |> assign_blank_form()}
  end

  def handle_event("use_totp", _params, socket) do
    {:noreply, socket |> assign(:mode, :totp) |> assign_blank_form()}
  end

  defp assign_blank_form(socket) do
    assign(socket, :form, to_form(%{"code" => ""}, as: "user"))
  end
end
