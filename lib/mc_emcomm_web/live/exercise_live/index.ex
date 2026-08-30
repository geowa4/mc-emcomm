defmodule McEmcommWeb.ExerciseLive.Index do
  use McEmcommWeb, :live_view

  alias McEmcomm.Exercises

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: "Exercises", exercises: Exercises.list_exercises())}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>Exercises</.header>

      <ul :if={@exercises != []} class="list bg-base-100 rounded-box border border-base-300 mt-4">
        <li :for={exercise <- @exercises} class="list-row">
          <div>
            <.link navigate={~p"/app/exercises/#{exercise.id}"} class="font-semibold link link-hover">
              {exercise.title}
            </.link>
            <div class="text-sm text-base-content/70">
              {Calendar.strftime(exercise.starts_at, "%B %d, %Y %I:%M %p")}
              <span class="badge badge-sm badge-ghost ml-2">{exercise.visibility}</span>
            </div>
          </div>
        </li>
      </ul>
      <p :if={@exercises == []} class="text-base-content/70 mt-4">No exercises yet.</p>
    </Layouts.app>
    """
  end
end
