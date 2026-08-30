defmodule McEmcomm.Exercises do
  @moduledoc """
  Exercises, their named geofenced locations, attachments, and attendance.

  Geofence matching (§10 of the spec) queries `exercise_locations` joined to
  exercises whose `starts_at`/`ends_at` window contains the given time, using
  `ST_DWithin` on geography (meters) ordered by `ST_Distance`, limit 1. No
  quadrant is computed geometrically.
  """

  import Ecto.Query, warn: false

  alias McEmcomm.Exercises.Exercise
  alias McEmcomm.Exercises.ExerciseAttachment
  alias McEmcomm.Exercises.ExerciseAttendance
  alias McEmcomm.Exercises.ExerciseLocation
  alias McEmcomm.Repo

  ## Exercises

  def list_exercises(opts \\ []) do
    Exercise
    |> maybe_filter_visibility(opts[:visibility])
    |> order_by([e], desc: e.starts_at)
    |> Repo.all()
  end

  defp maybe_filter_visibility(query, nil), do: query

  defp maybe_filter_visibility(query, visibility),
    do: where(query, [e], e.visibility == ^visibility)

  def get_exercise!(id) do
    Exercise
    |> Repo.get!(id)
    |> Repo.preload([:locations, :attachments, attendance: :member])
  end

  def change_exercise(%Exercise{} = exercise, attrs \\ %{}) do
    Exercise.changeset(exercise, attrs)
  end

  def create_exercise(attrs), do: %Exercise{} |> Exercise.changeset(attrs) |> Repo.insert()

  def update_exercise(%Exercise{} = exercise, attrs) do
    exercise |> Exercise.changeset(attrs) |> Repo.update()
  end

  def delete_exercise(%Exercise{} = exercise), do: Repo.delete(exercise)

  ## Locations

  def change_exercise_location(%ExerciseLocation{} = location, attrs \\ %{}) do
    ExerciseLocation.changeset(location, attrs)
  end

  def create_exercise_location(attrs) do
    %ExerciseLocation{} |> ExerciseLocation.changeset(attrs) |> Repo.insert()
  end

  def update_exercise_location(%ExerciseLocation{} = location, attrs) do
    location |> ExerciseLocation.changeset(attrs) |> Repo.update()
  end

  def delete_exercise_location(%ExerciseLocation{} = location), do: Repo.delete(location)

  @doc """
  Creates an exercise together with its locations in one transaction. When
  exactly one location is given without a name, it defaults to
  `"Primary Site"`.
  """
  def create_exercise_with_locations(exercise_attrs, location_attrs_list) do
    location_attrs_list = default_single_location_name(location_attrs_list)

    exercise_changeset = Exercise.changeset(%Exercise{}, exercise_attrs)

    Ecto.Multi.new()
    |> Ecto.Multi.insert(:exercise, exercise_changeset)
    |> Ecto.Multi.run(:locations, fn repo, %{exercise: exercise} ->
      results =
        Enum.map(location_attrs_list, fn attrs ->
          %ExerciseLocation{}
          |> ExerciseLocation.changeset(Map.put(attrs, "exercise_id", exercise.id))
          |> repo.insert()
        end)

      case Enum.find(results, &match?({:error, _}, &1)) do
        nil -> {:ok, Enum.map(results, fn {:ok, l} -> l end)}
        error -> error
      end
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{exercise: exercise, locations: locations}} ->
        {:ok, %{exercise | locations: locations}}

      {:error, _step, changeset, _} ->
        {:error, changeset}
    end
  end

  defp default_single_location_name([%{} = attrs]) do
    if Map.get(attrs, "name") in [nil, ""] do
      [Map.put(attrs, "name", "Primary Site")]
    else
      [attrs]
    end
  end

  defp default_single_location_name(list), do: list

  ## Attachments

  def change_exercise_attachment(%ExerciseAttachment{} = attachment, attrs \\ %{}) do
    ExerciseAttachment.changeset(attachment, attrs)
  end

  def create_exercise_attachment(attrs) do
    %ExerciseAttachment{} |> ExerciseAttachment.changeset(attrs) |> Repo.insert()
  end

  def delete_exercise_attachment(%ExerciseAttachment{} = attachment), do: Repo.delete(attachment)

  ## Attendance

  def list_attendance(exercise_id) do
    ExerciseAttendance
    |> where([a], a.exercise_id == ^exercise_id)
    |> preload(:member)
    |> Repo.all()
  end

  def change_attendance(%ExerciseAttendance{} = attendance, attrs \\ %{}) do
    ExerciseAttendance.changeset(attendance, attrs)
  end

  @doc "Records attendance if one doesn't already exist for this exercise/member pair."
  def record_attendance(exercise_id, member_id, source, opts \\ []) do
    attrs = %{
      exercise_id: exercise_id,
      member_id: member_id,
      source: source,
      sighting_id: opts[:sighting_id],
      recorded_at: opts[:recorded_at] || DateTime.utc_now()
    }

    %ExerciseAttendance{}
    |> ExerciseAttendance.changeset(attrs)
    |> Repo.insert(
      on_conflict: :nothing,
      conflict_target: [:exercise_id, :member_id]
    )
  end

  ## Geofence matching (§10)

  @doc """
  Finds the nearest active exercise location whose exercise window
  (`starts_at`..`ends_at`) contains `at` and whose `geofence_radius_m`
  contains `point`. Returns `{exercise_location, exercise}` or `nil`.
  """
  @spec match_location(Geo.Point.t(), DateTime.t()) :: {ExerciseLocation.t(), Exercise.t()} | nil
  def match_location(%Geo.Point{} = point, %DateTime{} = at) do
    query =
      from l in ExerciseLocation,
        join: e in Exercise,
        on: e.id == l.exercise_id,
        where: e.starts_at <= ^at and e.ends_at >= ^at,
        where: fragment("ST_DWithin(?, ?, ?)", l.point, ^point, l.geofence_radius_m),
        order_by: fragment("ST_Distance(?, ?)", l.point, ^point),
        limit: 1,
        select: {l, e}

    Repo.one(query)
  end
end
