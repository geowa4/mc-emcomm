defmodule McEmcommWeb.ExerciseLive.PublicIndex do
  use McEmcommWeb, :live_view

  alias McEmcomm.Exercises

  @impl true
  def mount(_params, _session, socket) do
    exercises = Exercises.list_exercises(visibility: :public)
    {:ok, assign(socket, page_title: "Exercises", exercises: exercises)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>Exercises</.header>

      <p class="text-base-content/70">
        Public exercise schedule. Approved members see full details, locations, and
        attachments in the <.link navigate={~p"/app/exercises"} class="link">member portal</.link>.
      </p>

      <ul :if={@exercises != []} class="list bg-base-100 rounded-box border border-base-300 mt-4">
        <li :for={exercise <- @exercises} class="list-row">
          <div>
            <.link navigate={~p"/exercises/#{exercise.id}"} class="font-semibold link link-hover">
              {exercise.title}
            </.link>
            <div class="text-sm text-base-content/70">
              {Calendar.strftime(exercise.starts_at, "%B %d, %Y %I:%M %p")}
            </div>
          </div>
        </li>
      </ul>
      <p :if={@exercises == []} class="text-base-content/70 mt-4">No upcoming public exercises.</p>
    </Layouts.app>
    """
  end
end
