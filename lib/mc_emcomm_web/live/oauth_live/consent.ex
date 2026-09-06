defmodule McEmcommWeb.OAuthLive.Consent do
  @moduledoc """
  The OAuth consent screen at `GET /oauth/authorize` (SPEC.md §28). It runs
  in the ordinary browser session: an anonymous visitor is sent through the
  normal login flow first and returned here with the same query string, and
  the CSRF protection is LiveView's own.

  The request is validated before anything renders. A bad client or
  redirect URI is a dead end (the user is never redirected to an unverified
  address); every other problem, and a Deny, goes back to the client as an
  OAuth error. Approval mints a 60-second single-use code bound to the user,
  client, redirect URI, PKCE challenge, resource, and the scopes actually
  granted — the requested scopes intersected with what the user's live role
  permits (`McEmcomm.OAuth.Scopes.effective/2`).
  """
  use McEmcommWeb, :live_view

  alias McEmcomm.OAuth
  alias McEmcomm.OAuth.AuthorizationCodes
  alias McEmcomm.OAuth.AuthorizationRequest
  alias McEmcomm.OAuth.Scopes

  @impl true
  def mount(params, _session, socket) do
    socket = assign(socket, page_title: "Authorize access", noindex: true)

    case AuthorizationRequest.validate(params) do
      {:ok, request} ->
        scope = socket.assigns.current_scope
        granted = Scopes.effective(request.scopes, scope)
        requested = if request.scopes == [], do: Scopes.all(), else: request.scopes

        {:ok,
         assign(socket,
           request: request,
           granted: granted,
           withheld: requested -- granted,
           loopback?: OAuth.loopback_redirect_uri?(request.redirect_uri),
           redirect_host: URI.parse(request.redirect_uri).host,
           error: nil
         )}

      {:error, {:redirect, redirect_uri, error, description, state}} ->
        {:ok,
         redirect(socket,
           external: AuthorizationRequest.error_url(redirect_uri, error, description, state)
         )}

      {:error, fatal} ->
        {:ok, assign(socket, request: nil, error: fatal)}
    end
  end

  @impl true
  def render(%{error: error} = assigns) when not is_nil(error) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} active_net={@active_net}>
      <div class="mx-auto max-w-lg space-y-4">
        <.header>Authorization request refused</.header>
        <p id="consent-error" role="alert">
          <%= if @error == :invalid_client do %>
            The application asking for access is not registered with this site.
          <% else %>
            The application asked to be sent to an address it did not register.
          <% end %>
          Nothing has been shared. Close this window and start over from the
          application.
        </p>
      </div>
    </Layouts.app>
    """
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} active_net={@active_net}>
      <div class="mx-auto max-w-lg space-y-6">
        <.header>
          Authorize {client_name(@request)}
          <:subtitle>
            <strong>{client_name(@request)}</strong>
            wants to act as <strong>{@current_scope.user.email}</strong>
            on Monroe County ARES/RACES. It will only ever be able to do what your
            account can do on the website.
          </:subtitle>
        </.header>

        <section :if={@granted != []} id="consent-granted" aria-labelledby="consent-granted-title">
          <h2 id="consent-granted-title" class="font-semibold">It will be able to</h2>
          <ul class="list-disc pl-6 mt-2 space-y-1">
            <li :for={scope <- @granted}>
              <span class="font-mono text-sm">{scope}</span>
              <span class="text-base-content/80">— {Scopes.description(scope)}</span>
            </li>
          </ul>
        </section>

        <section :if={@withheld != []} id="consent-withheld" aria-labelledby="consent-withheld-title">
          <h2 id="consent-withheld-title" class="font-semibold">Not available to your account</h2>
          <ul class="list-disc pl-6 mt-2 space-y-1 text-base-content/80">
            <li :for={scope <- @withheld}>
              <span class="font-mono text-sm">{scope}</span>
              <%= if scope == Scopes.membership() do %>
                — administrators only
              <% else %>
                — approved members only
              <% end %>
            </li>
          </ul>
        </section>

        <p :if={@granted == []} id="consent-no-access" role="alert" class="alert alert-warning">
          Your account is not an approved member, so there is nothing this application
          could do on your behalf. You can only decline.
        </p>

        <p class="text-sm text-base-content/80">
          After you approve, your browser will be sent to <span
            id="consent-redirect-host"
            class="font-mono"
          >{@redirect_host}</span>.
          <span :if={@loopback?}>
            That is an application running on this computer; make sure it is the one
            you just started.
          </span>
        </p>

        <div class="flex gap-2 flex-wrap">
          <.button
            :if={@granted != []}
            id="consent-approve"
            variant="primary"
            phx-click="approve"
            phx-disable-with="Approving…"
          >
            Approve
          </.button>
          <.button id="consent-deny" phx-click="deny">Deny</.button>
        </div>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def handle_event("approve", _params, %{assigns: %{granted: []}} = socket) do
    {:noreply, deny(socket)}
  end

  def handle_event("approve", _params, socket) do
    %{request: request, granted: granted, current_scope: scope} = socket.assigns

    {:ok, code} =
      AuthorizationCodes.issue(scope.user, %{
        client_id: request.client.client_id,
        redirect_uri: request.redirect_uri,
        code_challenge: request.code_challenge,
        resource: request.resource,
        scopes: granted
      })

    emit(:ok)
    {:noreply, redirect(socket, external: AuthorizationRequest.success_url(request, code))}
  end

  def handle_event("deny", _params, socket), do: {:noreply, deny(socket)}

  defp deny(socket) do
    request = socket.assigns.request
    emit(:denied)

    redirect(socket,
      external:
        AuthorizationRequest.error_url(
          request.redirect_uri,
          "access_denied",
          "The user declined the request.",
          request.state
        )
    )
  end

  defp client_name(%AuthorizationRequest{client: %{client_name: name}})
       when is_binary(name) and name != "",
       do: name

  defp client_name(_request), do: "an application"

  defp emit(outcome) do
    :telemetry.execute([:mc_emcomm, :mcp, :oauth], %{count: 1}, %{
      operation: :authorize,
      outcome: outcome
    })
  end
end
