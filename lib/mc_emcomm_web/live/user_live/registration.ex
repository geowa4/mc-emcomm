defmodule McEmcommWeb.UserLive.Registration do
  use McEmcommWeb, :live_view

  alias McEmcomm.Accounts
  alias McEmcomm.Accounts.User
  alias McEmcomm.Members.Member
  alias McEmcomm.Repo

  @types %{email: :string, name: :string, call_sign: :string}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} active_net={@active_net}>
      <div class="mx-auto max-w-sm">
        <div class="text-center">
          <.header>
            Register for an account
            <:subtitle>
              Already registered?
              <.link navigate={~p"/users/log-in"} class="font-semibold text-brand hover:underline">
                Log in
              </.link>
              to your account now.
            </:subtitle>
          </.header>
        </div>

        <.form for={@form} id="registration_form" phx-submit="save" phx-change="validate">
          <.input
            field={@form[:email]}
            type="email"
            label="Email"
            autocomplete="username"
            spellcheck="false"
            required
            phx-mounted={JS.focus()}
          />
          <.input field={@form[:name]} type="text" label="Full name" required />
          <.input
            field={@form[:call_sign]}
            type="text"
            label="Call sign (optional)"
            autocomplete="off"
          />
          <p class="text-sm text-base-content/70">
            Your account starts as <strong>pending</strong> until an EmComm admin approves it.
          </p>

          <.button phx-disable-with="Creating account..." class="btn btn-primary w-full">
            Create an account
          </.button>
        </.form>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, %{assigns: %{current_scope: %{user: user}}} = socket)
      when not is_nil(user) do
    {:ok, redirect(socket, to: McEmcommWeb.UserAuth.signed_in_path(socket))}
  end

  def mount(_params, _session, socket) do
    {:ok, assign_form(socket, registration_changeset(%{})), temporary_assigns: [form: nil]}
  end

  @impl true
  def handle_event("save", %{"user" => user_params}, socket) do
    case register(user_params) do
      {:ok, user} ->
        {:ok, _} =
          Accounts.deliver_login_instructions(
            user,
            &url(~p"/users/log-in/#{&1}")
          )

        {:noreply,
         socket
         |> put_flash(
           :info,
           "An email was sent to #{user.email}, please access it to confirm your account."
         )
         |> push_navigate(to: ~p"/users/log-in")}

      {:error, changeset} ->
        {:noreply, assign_form(socket, %{changeset | action: :insert})}
    end
  end

  def handle_event("validate", %{"user" => user_params}, socket) do
    changeset = user_params |> registration_changeset() |> Map.put(:action, :validate)
    {:noreply, assign_form(socket, changeset)}
  end

  defp registration_changeset(params) do
    {Map.new(@types, fn {field, _type} -> {field, nil} end), @types}
    |> Ecto.Changeset.cast(params, Map.keys(@types))
    |> Ecto.Changeset.validate_required([:email, :name])
    |> Ecto.Changeset.validate_format(:email, ~r/^[^@,;\s]+@[^@,;\s]+$/,
      message: "must have the @ sign and no spaces"
    )
  end

  defp register(params) do
    changeset = registration_changeset(params)

    if changeset.valid? do
      data = Ecto.Changeset.apply_changes(changeset)

      user_changeset = User.email_changeset(%User{}, %{email: data.email})

      Ecto.Multi.new()
      |> Ecto.Multi.insert(:user, user_changeset)
      |> Ecto.Multi.insert(:member, fn %{user: user} ->
        Member.registration_changeset(%Member{}, %{
          user_id: user.id,
          name: data.name,
          call_sign: data.call_sign
        })
      end)
      |> Repo.transaction()
      |> case do
        {:ok, %{user: user}} -> {:ok, user}
        {:error, :user, changeset, _} -> {:error, changeset}
        {:error, :member, changeset, _} -> {:error, changeset}
      end
    else
      {:error, %{changeset | action: :insert}}
    end
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    form = to_form(changeset, as: "user")
    assign(socket, form: form)
  end
end
