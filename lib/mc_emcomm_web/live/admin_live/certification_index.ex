defmodule McEmcommWeb.AdminLive.CertificationIndex do
  use McEmcommWeb, :live_view

  alias McEmcomm.Certifications
  alias McEmcomm.Certifications.Certification
  alias McEmcomm.Courses

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: "Certifications",
       certifications: Certifications.list_certifications(),
       courses: Courses.list_courses(),
       editing: nil,
       form: nil
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} active_net={@active_net}>
      <.header>
        Certifications
        <:actions>
          <.button phx-click="new" class="btn btn-primary">New certification</.button>
        </:actions>
      </.header>

      <.form
        :if={@form}
        for={@form}
        id="certification-form"
        phx-change="validate"
        phx-submit="save"
        class="max-w-md mb-6"
      >
        <.input field={@form[:name]} label="Name" required />
        <.input field={@form[:code]} label="Code (e.g. AUXC, COML, COMT)" />
        <.input field={@form[:description]} type="textarea" label="Description" />
        <.input
          field={@form[:prerequisite_course_id]}
          type="select"
          label="Prerequisite course"
          prompt="None"
          options={Enum.map(@courses, &{&1.name, &1.id})}
        />
        <.input field={@form[:requires_task_book]} type="checkbox" label="Requires task book" />
        <.input field={@form[:active]} type="checkbox" label="Active" />
        <.button class="btn btn-primary mt-2">Save</.button>
        <button type="button" phx-click="cancel" class="btn btn-ghost mt-2">Cancel</button>
      </.form>

      <.table id="certifications" rows={@certifications}>
        <:col :let={c} label="Name">{c.name}</:col>
        <:col :let={c} label="Code">{c.code}</:col>
        <:col :let={c} label="Prerequisite">
          {c.prerequisite_course && c.prerequisite_course.name}
        </:col>
        <:col :let={c} label="Active">{c.active}</:col>
        <:action :let={c}>
          <button
            type="button"
            class="link link-hover"
            phx-click="edit"
            phx-value-id={c.id}
            aria-label={"Edit #{c.name}"}
          >Edit</button>
        </:action>
        <:action :let={c}>
          <button
            type="button"
            class="link link-hover"
            phx-click="delete"
            phx-value-id={c.id}
            data-confirm="Delete this certification?"
            aria-label={"Delete #{c.name}"}
          >Delete</button>
        </:action>
      </.table>
    </Layouts.app>
    """
  end

  @impl true
  def handle_event("new", _params, socket) do
    {:noreply,
     assign(socket,
       editing: %Certification{},
       form: to_form(Certifications.change_certification(%Certification{}))
     )}
  end

  def handle_event("edit", %{"id" => id}, socket) do
    certification = Certifications.get_certification!(id)

    {:noreply,
     assign(socket,
       editing: certification,
       form: to_form(Certifications.change_certification(certification))
     )}
  end

  def handle_event("cancel", _params, socket),
    do: {:noreply, assign(socket, editing: nil, form: nil)}

  def handle_event("validate", %{"certification" => params}, socket) do
    form =
      socket.assigns.editing
      |> Certifications.change_certification(params)
      |> Map.put(:action, :validate)
      |> to_form()

    {:noreply, assign(socket, form: form)}
  end

  def handle_event("save", %{"certification" => params}, socket) do
    result =
      case socket.assigns.editing do
        %Certification{id: nil} -> Certifications.create_certification(params)
        certification -> Certifications.update_certification(certification, params)
      end

    case result do
      {:ok, _} ->
        {:noreply,
         assign(socket,
           editing: nil,
           form: nil,
           certifications: Certifications.list_certifications()
         )}

      {:error, changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  def handle_event("delete", %{"id" => id}, socket) do
    Certifications.get_certification!(id) |> Certifications.delete_certification()
    {:noreply, assign(socket, certifications: Certifications.list_certifications())}
  end
end
