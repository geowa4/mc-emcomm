defmodule McEmcommWeb.AdminLive.InventoryIndex do
  @moduledoc """
  Asset CRUD plus the QR code for each asset's sighting page. The QR SVG MUST
  encode a sighting URL, never a plain asset page (§9):
  `{MC_EMCOMM_QR_BASE_URL}/a/{public_id}/s`.
  """

  use McEmcommWeb, :live_view

  alias McEmcomm.Assets
  alias McEmcomm.Assets.Asset
  alias McEmcomm.Storage

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(
       page_title: "Inventory",
       assets: Assets.list_assets(),
       editing: nil,
       form: nil,
       qr_for: nil
     )
     |> allow_upload(:image,
       accept: ~w(.jpg .jpeg .png .webp),
       max_entries: 1,
       external: &presign_entry/2
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} active_net={@active_net}>
      <.header>
        Inventory
        <:actions>
          <.button phx-click="new" class="btn btn-primary">New asset</.button>
        </:actions>
      </.header>

      <form :if={@form} id="asset-form" phx-change="validate" phx-submit="save" class="max-w-md mb-6">
        <.input field={@form[:name]} label="Name" required />
        <.input field={@form[:description]} type="textarea" label="Description" />
        <.live_file_input upload={@uploads.image} />
        <.input field={@form[:active]} type="checkbox" label="Active" />
        <.button class="btn btn-primary mt-2">Save</.button>
        <button type="button" phx-click="cancel" class="btn btn-ghost mt-2">Cancel</button>
      </form>

      <.table id="assets" rows={@assets}>
        <:col :let={a} label="Name">{a.name}</:col>
        <:col :let={a} label="Public ID"><span class="font-mono">{a.public_id}</span></:col>
        <:col :let={a} label="Active">{a.active}</:col>
        <:action :let={a}>
          <.link phx-click="show_qr" phx-value-id={a.id}>QR code</.link>
        </:action>
        <:action :let={a}>
          <.link phx-click="edit" phx-value-id={a.id}>Edit</.link>
        </:action>
        <:action :let={a}>
          <.link phx-click="delete" phx-value-id={a.id} data-confirm="Delete this asset?">Delete</.link>
        </:action>
      </.table>

      <div :if={@qr_for} class="mt-6 max-w-xs">
        <h2 class="text-lg font-semibold">QR code &mdash; {@qr_for.name}</h2>
        <p class="text-sm text-base-content/70 font-mono break-all">{sighting_url(@qr_for)}</p>
        {raw(qr_svg(@qr_for))}
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def handle_event("new", _params, socket) do
    {:noreply,
     assign(socket, editing: %Asset{}, form: to_form(Assets.change_asset(%Asset{})), qr_for: nil)}
  end

  def handle_event("edit", %{"id" => id}, socket) do
    asset = Assets.get_asset!(id)

    {:noreply,
     assign(socket, editing: asset, form: to_form(Assets.change_asset(asset)), qr_for: nil)}
  end

  def handle_event("cancel", _params, socket),
    do: {:noreply, assign(socket, editing: nil, form: nil)}

  def handle_event("show_qr", %{"id" => id}, socket) do
    {:noreply, assign(socket, qr_for: Assets.get_asset!(id))}
  end

  def handle_event("validate", %{"asset" => params}, socket) do
    form =
      socket.assigns.editing
      |> Assets.change_asset(params)
      |> Map.put(:action, :validate)
      |> to_form()

    {:noreply, assign(socket, form: form)}
  end

  def handle_event("save", %{"asset" => params}, socket) do
    image =
      consume_uploaded_entries(socket, :image, fn %{key: key}, entry ->
        {:ok,
         %{
           image_key: key,
           image_filename: entry.client_name,
           image_content_type: entry.client_type
         }}
      end)
      |> List.first() || %{}

    params = Map.merge(params, Map.new(image, fn {k, v} -> {to_string(k), v} end))

    result =
      case socket.assigns.editing do
        %Asset{id: nil} -> Assets.create_asset(params)
        asset -> Assets.update_asset(asset, params)
      end

    case result do
      {:ok, _} ->
        {:noreply, assign(socket, editing: nil, form: nil, assets: Assets.list_assets())}

      {:error, changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  def handle_event("delete", %{"id" => id}, socket) do
    Assets.get_asset!(id) |> Assets.delete_asset()
    {:noreply, assign(socket, assets: Assets.list_assets())}
  end

  defp presign_entry(entry, socket) do
    key = Storage.build_key("asset-images", entry.client_name)
    presigned = Storage.presign_upload(key, entry.client_type)
    meta = %{uploader: "S3", key: key, url: presigned.url, fields: presigned.fields}
    {:ok, meta, socket}
  end

  defp sighting_url(asset) do
    base = Application.get_env(:mc_emcomm, :qr_base_url)
    "#{base}/a/#{asset.public_id}/s"
  end

  defp qr_svg(asset) do
    asset |> sighting_url() |> EQRCode.encode() |> EQRCode.svg(width: 240)
  end
end
