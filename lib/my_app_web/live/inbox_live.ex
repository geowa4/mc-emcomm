defmodule MyAppWeb.InboxLive do
  @moduledoc """
  Demonstrates the inbound email data flow end to end: the logged-in user
  sends an email from their own address to the app's Resend inbound address
  and watches it appear here.

  Nothing is stored. History is backfilled from Resend's Receiving API on
  mount and live updates arrive over PubSub from the webhook. Matching is by
  the spoofable `From` header, so this is a data-flow demonstration only and
  must never be used as an authentication or authorization signal.
  """
  use MyAppWeb, :live_view

  alias MyApp.Inbound
  alias MyApp.Inbound.Email

  @resend Application.compile_env(:my_app, :resend_client, MyApp.Resend)

  @impl true
  def mount(_params, _session, socket) do
    user_email = Inbound.normalize(socket.assigns.current_scope.user.email)

    if connected?(socket), do: Inbound.subscribe(user_email)

    {:ok,
     socket
     |> assign(page_title: "Inbox", user_email: user_email, loading: true)
     |> stream(:emails, [])
     |> start_async(:backfill, fn -> @resend.list_received_all() end)}
  end

  @impl true
  def handle_async(:backfill, {:ok, {:ok, emails}}, socket) do
    mine =
      emails
      |> Enum.map(&Email.from_api/1)
      |> Enum.filter(&(&1.from == socket.assigns.user_email))

    {:noreply, socket |> assign(loading: false) |> stream(:emails, mine)}
  end

  def handle_async(:backfill, _error, socket) do
    {:noreply,
     socket |> assign(loading: false) |> put_flash(:error, "Could not load inbox history")}
  end

  @impl true
  def handle_info({:email_received, meta}, socket) do
    {:noreply, stream_insert(socket, :emails, meta, at: 0)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        Inbox
        <:subtitle>
          Emails you sent to this app's inbound address, matched by your account email
          (<span id="inbox-address">{@user_email}</span>).
        </:subtitle>
      </.header>

      <p :if={@loading} id="inbox-loading" class="text-sm opacity-70">Loading history…</p>

      <table class="table">
        <thead>
          <tr>
            <th>Subject</th>
            <th>To</th>
            <th>Received</th>
          </tr>
        </thead>
        <tbody id="emails" phx-update="stream">
          <tr :for={{dom_id, email} <- @streams.emails} id={dom_id}>
            <td>{email.subject}</td>
            <td>{Enum.join(email.to, ", ")}</td>
            <td>{email.received_at}</td>
          </tr>
        </tbody>
      </table>
    </Layouts.app>
    """
  end
end
