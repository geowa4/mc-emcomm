defmodule McEmcommWeb.UserLive.Settings do
  use McEmcommWeb, :live_view

  require Logger

  on_mount {McEmcommWeb.UserAuth, :require_sudo_mode}

  alias McEmcomm.Accounts
  alias McEmcommWeb.ParamHelpers

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} active_net={@active_net}>
      <div class="text-center">
        <.header>
          Account
          <:subtitle>Manage the email addresses and password you use to log in</:subtitle>
        </.header>
      </div>

      <.form for={@email_form} id="email_form" phx-submit="update_email" phx-change="validate_email">
        <.input
          field={@email_form[:email]}
          type="email"
          label="Email"
          autocomplete="username"
          spellcheck="false"
          required
        />
        <.button variant="primary" phx-disable-with="Changing...">Change Email</.button>
      </.form>

      <div class="divider" />

      <section id="additional-emails" class="space-y-4" aria-labelledby="additional-emails-heading">
        <div>
          <h2 id="additional-emails-heading" class="font-semibold">Additional email addresses</h2>
          <p class="text-sm">
            You can log in with any of these. Account mail goes to your primary address, <span
              id="primary-email"
              class="font-semibold"
            >{@current_email}</span>.
          </p>
        </div>

        <ul id="user-emails" phx-update="stream" class="space-y-2">
          <li id="user-emails-empty" class="hidden only:block text-sm">
            You have no additional addresses.
          </li>
          <li
            :for={{id, user_email} <- @streams.user_emails}
            id={id}
            class="flex flex-wrap items-center gap-2"
          >
            <span class="grow break-all">{user_email.email}</span>
            <.button
              id={"make-primary-#{user_email.id}"}
              phx-click="make_primary"
              phx-value-id={user_email.id}
              aria-label={"Make #{user_email.email} your primary address"}
            >
              Make primary
            </.button>
            <.button
              id={"remove-email-#{user_email.id}"}
              phx-click="remove_email"
              phx-value-id={user_email.id}
              data-confirm={"Remove #{user_email.email} from your account?"}
              aria-label={"Remove #{user_email.email}"}
            >
              Remove
            </.button>
          </li>
        </ul>

        <.form
          for={@add_email_form}
          id="add_email_form"
          phx-submit="add_email"
          phx-change="validate_add_email"
        >
          <.input
            field={@add_email_form[:email]}
            type="email"
            label="Add an email address"
            autocomplete="email"
            spellcheck="false"
            required
          />
          <p class="text-sm">
            We will send a confirmation link to the address. If it already belongs to another
            account of yours, the link lets you merge that account into this one.
          </p>
          <.button variant="primary" phx-disable-with="Sending...">Add Email</.button>
        </.form>
      </section>

      <div class="divider" />

      <.form
        for={@password_form}
        id="password_form"
        action={~p"/users/update-password"}
        method="post"
        phx-change="validate_password"
        phx-submit="update_password"
        phx-trigger-action={@trigger_submit}
      >
        <input
          name={@password_form[:email].name}
          type="hidden"
          id="hidden_user_email"
          spellcheck="false"
          value={@current_email}
        />
        <.input
          :if={@has_password?}
          field={@password_form[:current_password]}
          type="password"
          label="Current password"
          autocomplete="current-password"
          spellcheck="false"
          required
        />
        <.input
          field={@password_form[:password]}
          type="password"
          label="New password"
          autocomplete="new-password"
          spellcheck="false"
          required
        />
        <.input
          field={@password_form[:password_confirmation]}
          type="password"
          label="Confirm new password"
          autocomplete="new-password"
          spellcheck="false"
        />
        <.button variant="primary" phx-disable-with="Saving...">
          {if @has_password?, do: "Change Password", else: "Set Password"}
        </.button>
      </.form>

      <div class="divider" />

      <section id="settings-two-factor" class="space-y-2">
        <p>
          Two-factor authentication is <span id="settings-two-factor-status" class="font-semibold">
            {if @totp_enabled?, do: "on", else: "off"}
          </span>.
        </p>
        <.link
          id="settings-two-factor-link"
          navigate={~p"/users/settings/two-factor"}
          class="btn btn-soft"
        >
          Manage two-factor authentication
        </.link>
      </section>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"token" => token}, _session, socket) do
    socket =
      case Accounts.update_user_email(socket.assigns.current_scope.user, token) do
        {:ok, _user} ->
          put_flash(socket, :info, "Email changed successfully.")

        {:error, _} ->
          put_flash(socket, :error, "Email change link is invalid or it has expired.")
      end

    {:ok, push_navigate(socket, to: ~p"/users/settings")}
  end

  def mount(_params, _session, socket) do
    user = socket.assigns.current_scope.user
    email_changeset = Accounts.change_user_email(user, %{}, validate_unique: false)
    password_changeset = Accounts.change_user_password(user, %{}, hash_password: false)

    socket =
      socket
      |> assign(:page_title, "Account")
      |> assign(:current_email, user.email)
      |> assign(:has_password?, is_binary(user.hashed_password))
      |> assign(:email_form, to_form(email_changeset))
      |> assign(:add_email_form, to_form(Accounts.change_user_additional_email(user)))
      |> stream(:user_emails, Accounts.list_user_emails(user))
      |> assign(:password_form, to_form(password_changeset))
      |> assign(:totp_enabled?, Accounts.totp_enabled?(user))
      |> assign(:trigger_submit, false)

    {:ok, socket}
  end

  @impl true
  def handle_event("validate_email", params, socket) do
    %{"user" => user_params} = params

    email_form =
      socket.assigns.current_scope.user
      |> Accounts.change_user_email(user_params, validate_unique: false)
      |> Map.put(:action, :validate)
      |> to_form()

    {:noreply, assign(socket, email_form: email_form)}
  end

  def handle_event("update_email", params, socket) do
    %{"user" => user_params} = params
    user = socket.assigns.current_scope.user
    true = Accounts.sudo_mode?(user)

    case Accounts.change_user_email(user, user_params) do
      %{valid?: true} = changeset ->
        {:noreply, flash_update_email_delivery(socket, changeset, user)}

      changeset ->
        {:noreply, assign(socket, :email_form, to_form(changeset, action: :insert))}
    end
  end

  def handle_event("validate_add_email", %{"user_email" => params}, socket) do
    add_email_form =
      socket.assigns.current_scope.user
      |> Accounts.change_user_additional_email(params)
      |> Map.put(:action, :validate)
      |> to_form()

    {:noreply, assign(socket, add_email_form: add_email_form)}
  end

  def handle_event("add_email", %{"user_email" => params}, socket) do
    user = socket.assigns.current_scope.user
    true = Accounts.sudo_mode?(user)

    case Accounts.change_user_additional_email(user, params) do
      %{valid?: true} = changeset ->
        email = Ecto.Changeset.get_field(changeset, :email)

        {:noreply,
         socket
         |> flash_add_email_delivery(user, email)
         |> assign(:add_email_form, to_form(Accounts.change_user_additional_email(user)))}

      changeset ->
        {:noreply, assign(socket, :add_email_form, to_form(changeset, action: :insert))}
    end
  end

  def handle_event("remove_email", %{"id" => id}, socket) do
    user = socket.assigns.current_scope.user
    true = Accounts.sudo_mode?(user)

    case Accounts.remove_user_email(user, ParamHelpers.id(id)) do
      {:ok, user_email} ->
        {:noreply,
         socket
         |> stream_delete(:user_emails, user_email)
         |> put_flash(:info, "#{user_email.email} was removed from your account.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "That address could not be removed.")}
    end
  end

  def handle_event("make_primary", %{"id" => id}, socket) do
    user = socket.assigns.current_scope.user
    true = Accounts.sudo_mode?(user)

    case Accounts.make_email_primary(user, ParamHelpers.id(id)) do
      {:ok, user} ->
        # A full page load, so every assign derived from the user is rebuilt.
        {:noreply,
         socket
         |> put_flash(:info, "#{user.email} is now your primary address.")
         |> redirect(to: ~p"/users/settings")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "That address could not be made primary.")}
    end
  end

  def handle_event("validate_password", params, socket) do
    %{"user" => user_params} = params

    # Argon2 verification of the current password waits for submit; every
    # keystroke only checks shape and presence.
    password_form =
      socket.assigns.current_scope.user
      |> Accounts.change_user_password(user_params,
        hash_password: false,
        verify_current_password: false
      )
      |> Map.put(:action, :validate)
      |> to_form()

    {:noreply, assign(socket, password_form: password_form)}
  end

  def handle_event("update_password", params, socket) do
    %{"user" => user_params} = params
    user = socket.assigns.current_scope.user
    true = Accounts.sudo_mode?(user)

    case Accounts.change_user_password(user, user_params) do
      %{valid?: true} = changeset ->
        {:noreply, assign(socket, trigger_submit: true, password_form: to_form(changeset))}

      changeset ->
        {:noreply, assign(socket, password_form: to_form(changeset, action: :insert))}
    end
  end

  # The answer is the same whether or not the address belongs to another
  # account, so the form cannot be used to find out which addresses have one.
  defp flash_add_email_delivery(socket, user, email) do
    case Accounts.deliver_additional_email_instructions(
           user,
           email,
           &url(~p"/users/settings/emails/#{&1}")
         ) do
      {:ok, _email} ->
        put_flash(socket, :info, "A confirmation link has been sent to #{email}.")

      {:error, reason} ->
        Logger.error(
          "Could not deliver add-email instructions for user #{user.id}: #{inspect(reason)}"
        )

        put_flash(
          socket,
          :error,
          "The confirmation email could not be sent. Please try again later."
        )
    end
  end

  defp flash_update_email_delivery(socket, changeset, user) do
    changeset
    |> Ecto.Changeset.apply_action!(:insert)
    |> Accounts.deliver_user_update_email_instructions(
      user.email,
      &url(~p"/users/settings/confirm-email/#{&1}")
    )
    |> case do
      {:ok, _email} ->
        put_flash(
          socket,
          :info,
          "A link to confirm your email change has been sent to the new address."
        )

      {:error, reason} ->
        Logger.error(
          "Could not deliver email change instructions for user #{user.id}: #{inspect(reason)}"
        )

        put_flash(
          socket,
          :error,
          "The confirmation email could not be sent to the new address. Please try again later."
        )
    end
  end
end
