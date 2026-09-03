defmodule McEmcommWeb.AdminLive.CourseIndex do
  use McEmcommWeb, :live_view

  alias McEmcomm.Courses
  alias McEmcomm.Courses.Course

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: "Courses",
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
        Courses
        <:actions>
          <.button phx-click="new" class="btn btn-primary">New course</.button>
        </:actions>
      </.header>

      <.form
        :if={@form}
        for={@form}
        id="course-form"
        phx-change="validate"
        phx-submit="save"
        class="max-w-md mb-6"
      >
        <.input field={@form[:name]} label="Name" required />
        <.input field={@form[:code]} label="Code (e.g. IS-100)" />
        <.input field={@form[:description]} type="textarea" label="Description" />
        <.input field={@form[:active]} type="checkbox" label="Active" />
        <.button class="btn btn-primary mt-2">Save</.button>
        <button type="button" phx-click="cancel" class="btn btn-ghost mt-2">Cancel</button>
      </.form>

      <.table id="courses" rows={@courses}>
        <:col :let={c} label="Name">{c.name}</:col>
        <:col :let={c} label="Code">{c.code}</:col>
        <:col :let={c} label="Active">{c.active}</:col>
        <:action :let={c}>
          <.link phx-click="edit" phx-value-id={c.id}>Edit</.link>
        </:action>
        <:action :let={c}>
          <.link phx-click="delete" phx-value-id={c.id} data-confirm="Delete this course?">Delete</.link>
        </:action>
      </.table>
    </Layouts.app>
    """
  end

  @impl true
  def handle_event("new", _params, socket) do
    {:noreply,
     assign(socket, editing: %Course{}, form: to_form(Courses.change_course(%Course{})))}
  end

  def handle_event("edit", %{"id" => id}, socket) do
    course = Courses.get_course!(id)
    {:noreply, assign(socket, editing: course, form: to_form(Courses.change_course(course)))}
  end

  def handle_event("cancel", _params, socket),
    do: {:noreply, assign(socket, editing: nil, form: nil)}

  def handle_event("validate", %{"course" => params}, socket) do
    form =
      socket.assigns.editing
      |> Courses.change_course(params)
      |> Map.put(:action, :validate)
      |> to_form()

    {:noreply, assign(socket, form: form)}
  end

  def handle_event("save", %{"course" => params}, socket) do
    result =
      case socket.assigns.editing do
        %Course{id: nil} -> Courses.create_course(params)
        course -> Courses.update_course(course, params)
      end

    case result do
      {:ok, _} ->
        {:noreply, assign(socket, editing: nil, form: nil, courses: Courses.list_courses())}

      {:error, changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  def handle_event("delete", %{"id" => id}, socket) do
    Courses.get_course!(id) |> Courses.delete_course()
    {:noreply, assign(socket, courses: Courses.list_courses())}
  end
end
