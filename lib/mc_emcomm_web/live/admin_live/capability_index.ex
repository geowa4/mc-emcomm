defmodule McEmcommWeb.AdminLive.CapabilityIndex do
  use McEmcommWeb, :live_view

  alias McEmcomm.Capabilities
  alias McEmcomm.Capabilities.Capability

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: "Capabilities",
       capabilities: Capabilities.list_capabilities(),
       editing: nil,
       form: nil
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} active_net={@active_net}>
      <.header>
        Capabilities
        <:actions>
          <.button phx-click="new" class="btn btn-primary">New capability</.button>
        </:actions>
      </.header>

      <.form
        :if={@form}
        for={@form}
        id="capability-form"
        phx-change="validate"
        phx-submit="save"
        class="max-w-md mb-6"
      >
        <.input field={@form[:name]} label="Name" required />
        <.input field={@form[:code]} label="Code" />
        <.input field={@form[:description]} type="textarea" label="Description" />
        <.input field={@form[:active]} type="checkbox" label="Active" />
        <.button class="btn btn-primary mt-2">Save</.button>
        <button type="button" phx-click="cancel" class="btn btn-ghost mt-2">Cancel</button>
      </.form>

      <.table id="capabilities" rows={@capabilities}>
        <:col :let={c} label="Name">{c.name}</:col>
        <:col :let={c} label="Code">{c.code}</:col>
        <:col :let={c} label="Active">{c.active}</:col>
        <:action :let={c}>
          <.link phx-click="edit" phx-value-id={c.id}>Edit</.link>
        </:action>
        <:action :let={c}>
          <.link phx-click="delete" phx-value-id={c.id} data-confirm="Delete this capability?">Delete</.link>
        </:action>
      </.table>
    </Layouts.app>
    """
  end

  @impl true
  def handle_event("new", _params, socket) do
    {:noreply,
     assign(socket,
       editing: %Capability{},
       form: to_form(Capabilities.change_capability(%Capability{}))
     )}
  end

  def handle_event("edit", %{"id" => id}, socket) do
    capability = Capabilities.get_capability!(id)

    {:noreply,
     assign(socket,
       editing: capability,
       form: to_form(Capabilities.change_capability(capability))
     )}
  end

  def handle_event("cancel", _params, socket),
    do: {:noreply, assign(socket, editing: nil, form: nil)}

  def handle_event("validate", %{"capability" => params}, socket) do
    form =
      socket.assigns.editing
      |> Capabilities.change_capability(params)
      |> Map.put(:action, :validate)
      |> to_form()

    {:noreply, assign(socket, form: form)}
  end

  def handle_event("save", %{"capability" => params}, socket) do
    result =
      case socket.assigns.editing do
        %Capability{id: nil} -> Capabilities.create_capability(params)
        capability -> Capabilities.update_capability(capability, params)
      end

    case result do
      {:ok, _} ->
        {:noreply,
         assign(socket, editing: nil, form: nil, capabilities: Capabilities.list_capabilities())}

      {:error, changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  def handle_event("delete", %{"id" => id}, socket) do
    Capabilities.get_capability!(id) |> Capabilities.delete_capability()
    {:noreply, assign(socket, capabilities: Capabilities.list_capabilities())}
  end
end
