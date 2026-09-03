defmodule McEmcommWeb.SightingLive.Show do
  @moduledoc """
  The public sighting page (`/a/:public_id/s`). Renders ONLY the asset image,
  name, and the sighting form (spec §9) — no recent-sightings log, map, or
  metadata; those live at `/app/inventory/:public_id` for members/admins.

  Update point 0 (HTTP mount) already ran in `McEmcommWeb.Plugs.RecordSighting`
  before this LiveView's disconnected render; this module only handles
  update points 1 (via the `SightingClient` JS hook) and 2 (form submit).
  """

  use McEmcommWeb, :live_view

  alias McEmcomm.Assets
  alias McEmcomm.Sightings
  alias McEmcomm.Storage
  alias McEmcommWeb.MapHelpers

  @impl true
  def mount(%{"public_id" => public_id}, session, socket) do
    asset = Assets.get_asset_by_public_id(public_id)

    # The sighting must be the one this session's scan of *this* asset
    # created; a session left over from another asset does not carry over.
    sighting =
      asset &&
        Sightings.get_for_session(
          session["sighting_id"],
          session["sighting_session_token"],
          asset.id
        )

    cond do
      is_nil(asset) or not asset.active ->
        {:ok,
         socket
         |> put_flash(:error, "That asset couldn't be found.")
         |> push_navigate(to: ~p"/")}

      is_nil(sighting) ->
        {:ok,
         socket
         |> put_flash(
           :error,
           "Something went wrong recording your visit. Please rescan the QR code."
         )
         |> push_navigate(to: ~p"/")}

      true ->
        {:ok,
         assign(socket,
           page_title: asset.name,
           asset: asset,
           image_url: asset.image_key && Storage.presign_download_url(asset.image_key),
           sighting: sighting,
           submitted: not is_nil(sighting.submitted_at),
           form:
             to_form(
               %{
                 "call_sign" => known_call_sign(socket.assigns.current_scope),
                 "note" => "",
                 "claimed_responsibility" => false
               },
               as: "sighting"
             )
         )}
    end
  end

  defp known_call_sign(%{member: %{call_sign: call_sign}}) when is_binary(call_sign),
    do: call_sign

  defp known_call_sign(_scope), do: ""

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} active_net={@active_net}>
      <div id="sighting-client" phx-hook="SightingClient" class="hidden"></div>

      <div class="max-w-md mx-auto">
        <img :if={@image_url} src={@image_url} alt={@asset.name} class="rounded-box w-full" />
        <h1 class="text-2xl font-bold mt-4">{@asset.name}</h1>
        <p :if={@asset.description} class="text-base-content/70">{@asset.description}</p>

        <div :if={@submitted} class="alert alert-success mt-6">
          Thanks — this sighting has been recorded.
        </div>

        <.form :if={!@submitted} for={@form} id="sighting-form" phx-submit="submit" class="mt-6">
          <.input field={@form[:call_sign]} label="Call sign" required />
          <.input field={@form[:note]} type="textarea" label="Note (optional)" />
          <.input
            field={@form[:claimed_responsibility]}
            type="checkbox"
            label="I am claiming responsibility for this asset"
          />
          <.button phx-disable-with="Submitting..." class="btn btn-primary w-full mt-2">
            Submit sighting
          </.button>
        </.form>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def handle_event("client_env", params, socket) do
    Sightings.record_client_env(socket.assigns.sighting, %{
      "connected_at" => DateTime.utc_now(),
      "timezone" => params["timezone"],
      "screen_w" => params["screen_w"],
      "screen_h" => params["screen_h"],
      "device_pixel_ratio" => params["device_pixel_ratio"],
      "languages" => params["languages"],
      "connection_type" => params["connection_type"],
      "touch" => params["touch"]
    })

    {:noreply, socket}
  end

  def handle_event("geolocation", params, socket) do
    {:ok, sighting} =
      Sightings.record_geolocation(socket.assigns.sighting, %{
        "located_at" => DateTime.utc_now(),
        "point" => MapHelpers.point(params["lat"], params["lng"]),
        "accuracy" => params["accuracy"],
        "altitude" => params["altitude"],
        "heading" => params["heading"],
        "speed" => params["speed"]
      })

    {:noreply, assign(socket, sighting: sighting)}
  end

  def handle_event("geolocation_denied", _params, socket) do
    {:ok, sighting} =
      Sightings.record_geolocation(socket.assigns.sighting, %{"geo_denied" => true})

    {:noreply, assign(socket, sighting: sighting)}
  end

  def handle_event("submit", %{"sighting" => params}, socket) do
    opts = [current_member: socket.assigns.current_scope && socket.assigns.current_scope.member]

    case Sightings.submit(socket.assigns.sighting, params, opts) do
      {:ok, sighting} ->
        {:noreply, assign(socket, sighting: sighting, submitted: true)}

      {:error, changeset} ->
        {:noreply, assign(socket, form: to_form(changeset, as: "sighting"))}
    end
  end
end
