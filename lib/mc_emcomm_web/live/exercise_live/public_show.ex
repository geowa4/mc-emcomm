defmodule McEmcommWeb.ExerciseLive.PublicShow do
  use McEmcommWeb, :live_view

  alias McEmcomm.Exercises

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    case fetch_public_exercise(id) do
      {:ok, exercise} ->
        {:ok, assign(socket, page_title: exercise.title, exercise: exercise)}

      :error ->
        {:ok,
         socket
         |> put_flash(:error, "That exercise isn't public.")
         |> push_navigate(to: ~p"/exercises")}
    end
  end

  defp fetch_public_exercise(id) do
    exercise = Exercises.get_exercise!(id)
    if exercise.visibility == :public, do: {:ok, exercise}, else: :error
  rescue
    Ecto.NoResultsError -> :error
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        {@exercise.title}
        <:subtitle>
          {Calendar.strftime(@exercise.starts_at, "%B %d, %Y %I:%M %p")} &ndash; {Calendar.strftime(
            @exercise.ends_at,
            "%I:%M %p"
          )}
        </:subtitle>
      </.header>

      <p :if={@exercise.description}>{@exercise.description}</p>

      <.link navigate={~p"/exercises"} class="link mt-4 inline-block">&larr; Back to exercises</.link>
    </Layouts.app>
    """
  end
end
