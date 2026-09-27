defmodule McEmcommWeb.UserLive.EmailClaim do
  @moduledoc """
  Where the confirmation link for an additional email address lands.

  An address nobody else holds is added on arrival. One that belongs to
  another account opens the merge review instead: the user picks which
  profile details to bring over, and confirming merges that account into
  this one and deactivates it (`McEmcomm.AccountMerge`).

  The link only works from the account that asked for it, so it is not
  behind sudo mode: asking for the link was.
  """
  use McEmcommWeb, :live_view

  alias McEmcomm.AccountMerge
  alias McEmcomm.Accounts
  alias McEmcommWeb.UserAuth

  @groups [
    profile: "Profile details",
    capabilities: "Capabilities",
    courses: "Courses",
    certifications: "Certifications"
  ]

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} active_net={@active_net}>
      <div class="text-center">
        <.header>
          Merge accounts
          <:subtitle>
            <span id="merge-other-email" class="font-semibold">{@plan.other.email}</span>
            already belongs to another account
          </:subtitle>
        </.header>
      </div>

      <section :if={@plan.blocked} id="merge-blocked" class="space-y-4">
        <div class="alert alert-warning" role="alert">
          <.icon name="hero-shield-exclamation" class="size-6 shrink-0" />
          <p>
            That account is protected by two-factor authentication, so it cannot be merged from
            an email link. Log in to it and turn two-factor authentication off, then ask for a
            new link from your account settings.
          </p>
        </div>
        <.button id="merge-back" navigate={~p"/"}>Back to the site</.button>
      </section>

      <section :if={!@plan.blocked} id="merge-review" class="space-y-6">
        <p>
          If both accounts are yours, you can merge them. Everything is kept on the account you
          are logged in to, <span class="font-semibold">{@current_scope.user.email}</span>,
          and the other account is deactivated.
        </p>

        <ul id="merge-effects" class="list-disc ps-6 space-y-1">
          <li>
            Every email address of the other account becomes an additional address of yours.
          </li>
          <li :if={@plan.other_member}>
            Its attendance, RSVPs, net check-ins, and sightings move to your profile.
          </li>
          <li :if={@plan.adopts_profile?} id="merge-adopts-profile">
            You have no member profile yet, so its profile
            ({@plan.other_member.name}, {status_label(@plan.other_member.status)}) becomes yours.
          </li>
          <li :if={@plan.gains.approved?} id="merge-gains-approved">
            Your membership becomes approved, as it is on the other account.
          </li>
          <li :if={@plan.gains.positions != []} id="merge-gains-positions">
            You take over its leadership positions: {Enum.map_join(
              @plan.gains.positions,
              ", ",
              & &1.name
            )}.
          </li>
          <li :if={@plan.gains.admin?} id="merge-gains-admin">
            You become an administrator, as the other account is.
          </li>
          <li>
            The other account can no longer be used to log in, and apps connected to it are
            disconnected.
          </li>
        </ul>

        <.form for={@form} id="merge-form" phx-submit="merge" class="space-y-6">
          <fieldset
            :for={{group, title, items} <- @groups}
            id={"merge-group-#{group}"}
            class="space-y-2"
          >
            <legend class="font-semibold">{title}</legend>
            <p :if={group == :profile} class="text-sm">
              Tick what to bring over from the other account. A ticked item replaces what you
              have now.
            </p>
            <label
              :for={item <- items}
              id={"merge-item-#{dom_key(item.key)}"}
              class="flex items-start gap-3 rounded-box border border-base-300 p-3"
            >
              <input
                type="checkbox"
                name="merge[items][]"
                value={item.key}
                checked={item.default}
                class="checkbox mt-1"
              />
              <span class="grow">
                <span class="font-semibold">{item.label}</span>
                <span class="block">Bring over: {item.theirs}</span>
                <span class="block text-sm">
                  {if item.mine, do: "Replaces yours: #{item.mine}", else: "You have none"}
                </span>
              </span>
            </label>
          </fieldset>

          <p
            :if={(@groups == [] and @plan.other_member) && !@plan.adopts_profile?}
            id="merge-no-items"
          >
            The other profile has no details that differ from yours.
          </p>

          <div class="alert alert-warning" role="note">
            <.icon name="hero-exclamation-triangle" class="size-6 shrink-0" />
            <p>Merging cannot be undone.</p>
          </div>

          <div class="flex flex-wrap gap-2">
            <.button id="merge-submit" variant="primary" phx-disable-with="Merging...">
              Merge accounts
            </.button>
            <.button id="merge-cancel" navigate={~p"/"}>Cancel</.button>
          </div>
        </.form>
      </section>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"token" => token}, _session, socket) do
    user = socket.assigns.current_scope.user

    case Accounts.confirm_additional_email(user, token) do
      {:ok, user_email} ->
        {:ok,
         socket
         |> put_flash(:info, "#{user_email.email} was added to your account.")
         |> push_navigate(to: landing_path(user))}

      {:merge, other} ->
        plan = AccountMerge.plan(user, other)

        {:ok,
         socket
         |> assign(:page_title, "Merge accounts")
         |> assign(:noindex, true)
         |> assign(:token, token)
         |> assign(:plan, plan)
         |> assign(:groups, groups(plan))
         |> assign(:form, to_form(%{}, as: :merge))}

      {:error, :invalid} ->
        {:ok,
         socket
         |> put_flash(:error, "Email confirmation link is invalid or it has expired.")
         |> push_navigate(to: landing_path(user))}
    end
  end

  @impl true
  def handle_event("merge", params, socket) do
    user = socket.assigns.current_scope.user

    case AccountMerge.merge(user, socket.assigns.token, selected_items(params)) do
      {:ok, %{expired_tokens: expired_tokens}} ->
        UserAuth.disconnect_sessions(expired_tokens)

        # A full page load, so the scope (profile, standing) is rebuilt.
        {:noreply,
         socket
         |> put_flash(:info, "The accounts were merged.")
         |> redirect(to: ~p"/")}

      {:error, :two_factor} ->
        {:noreply, assign(socket, :plan, %{socket.assigns.plan | blocked: :two_factor})}

      {:error, :invalid} ->
        {:noreply,
         socket
         |> put_flash(:error, "Email confirmation link is invalid or it has expired.")
         |> redirect(to: ~p"/")}
    end
  end

  # Nothing ticked submits no `merge` key at all.
  defp selected_items(%{"merge" => %{"items" => items}}) when is_list(items) do
    Enum.filter(items, &is_binary/1)
  end

  defp selected_items(_params), do: []

  defp groups(plan) do
    for {group, title} <- @groups,
        items = Enum.filter(plan.items, &(&1.group == group)),
        items != [] do
      {group, title, items}
    end
  end

  # The settings page wants a recent login; a link opened later lands on the
  # home page rather than on a request to log in again.
  defp landing_path(user) do
    if Accounts.sudo_mode?(user, -10), do: ~p"/users/settings", else: ~p"/"
  end

  defp dom_key(key), do: String.replace(key, ":", "-")

  defp status_label(status), do: status |> to_string() |> String.capitalize()
end
