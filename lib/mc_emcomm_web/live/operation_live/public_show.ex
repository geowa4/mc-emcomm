defmodule McEmcommWeb.OperationLive.PublicShow do
  use McEmcommWeb, :live_view

  alias McEmcomm.Operations

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    case fetch_public_operation(id) do
      {:ok, operation} ->
        {:ok, assign(socket, page_title: operation.title, operation: operation)}

      :error ->
        {:ok,
         socket
         |> put_flash(:error, "That operation isn't public.")
         |> push_navigate(to: ~p"/operations")}
    end
  end

  defp fetch_public_operation(id) do
    operation = Operations.get_operation!(id)
    if operation.visibility == :public, do: {:ok, operation}, else: :error
  rescue
    Ecto.NoResultsError -> :error
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} active_net={@active_net}>
      <.header>
        {@operation.title}
        <:subtitle>
          {Calendar.strftime(@operation.starts_at, "%B %d, %Y %I:%M %p")} &ndash; {Calendar.strftime(
            @operation.ends_at,
            "%I:%M %p"
          )}
        </:subtitle>
      </.header>

      <p :if={@operation.description}>{@operation.description}</p>

      <.link navigate={~p"/operations"} class="link mt-4 inline-block">&larr; Back to operations</.link>
    </Layouts.app>
    """
  end
end
