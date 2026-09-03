defmodule McEmcommWeb.InventoryLive.Index do
  use McEmcommWeb, :live_view

  alias McEmcomm.Assets

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: "Inventory", assets: Assets.list_assets(active_only: true))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} active_net={@active_net}>
      <.header>Inventory</.header>

      <.table
        id="assets"
        rows={@assets}
        row_click={fn a -> JS.navigate(~p"/app/inventory/#{a.public_id}") end}
      >
        <:col :let={a} label="Name">
          <.link navigate={~p"/app/inventory/#{a.public_id}"} class="link link-hover">{a.name}</.link>
        </:col>
        <:col :let={a} label="Public ID"><span class="font-mono">{a.public_id}</span></:col>
      </.table>
    </Layouts.app>
    """
  end
end
