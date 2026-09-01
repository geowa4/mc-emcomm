defmodule McEmcomm.Operations do
  @moduledoc """
  Operations, their named geofenced locations, attachments, and attendance.

  Geofence matching (§10 of the spec) queries `operation_locations` joined to
  operations whose `starts_at`/`ends_at` window contains the given time, using
  `ST_DWithin` on geography (meters) ordered by `ST_Distance`, limit 1.
  """

  import Ecto.Query, warn: false

  alias McEmcomm.Operations.Operation
  alias McEmcomm.Operations.OperationAttachment
  alias McEmcomm.Operations.OperationAttendance
  alias McEmcomm.Operations.OperationLocation
  alias McEmcomm.Repo

  ## Operations

  def list_operations(opts \\ []) do
    Operation
    |> maybe_filter_visibility(opts[:visibility])
    |> order_by([e], desc: e.starts_at)
    |> Repo.all()
  end

  defp maybe_filter_visibility(query, nil), do: query

  defp maybe_filter_visibility(query, visibility),
    do: where(query, [e], e.visibility == ^visibility)

  def get_operation!(id) do
    Operation
    |> Repo.get!(id)
    |> Repo.preload([:locations, :attachments, attendance: :member])
  end

  def change_operation(%Operation{} = operation, attrs \\ %{}) do
    Operation.changeset(operation, attrs)
  end

  def create_operation(attrs), do: %Operation{} |> Operation.changeset(attrs) |> Repo.insert()

  def update_operation(%Operation{} = operation, attrs) do
    operation |> Operation.changeset(attrs) |> Repo.update()
  end

  def delete_operation(%Operation{} = operation), do: Repo.delete(operation)

  ## Locations

  def change_operation_location(%OperationLocation{} = location, attrs \\ %{}) do
    OperationLocation.changeset(location, attrs)
  end

  def create_operation_location(attrs) do
    %OperationLocation{} |> OperationLocation.changeset(attrs) |> Repo.insert()
  end

  def update_operation_location(%OperationLocation{} = location, attrs) do
    location |> OperationLocation.changeset(attrs) |> Repo.update()
  end

  def delete_operation_location(%OperationLocation{} = location), do: Repo.delete(location)

  @doc """
  Creates an operation together with its locations in one transaction. When
  exactly one location is given without a name, it defaults to
  `"Primary Site"`.
  """
  def create_operation_with_locations(operation_attrs, location_attrs_list) do
    location_attrs_list = default_single_location_name(location_attrs_list)

    operation_changeset = Operation.changeset(%Operation{}, operation_attrs)

    Ecto.Multi.new()
    |> Ecto.Multi.insert(:operation, operation_changeset)
    |> Ecto.Multi.run(:locations, fn repo, %{operation: operation} ->
      results =
        Enum.map(location_attrs_list, fn attrs ->
          %OperationLocation{}
          |> OperationLocation.changeset(Map.put(attrs, "operation_id", operation.id))
          |> repo.insert()
        end)

      case Enum.find(results, &match?({:error, _}, &1)) do
        nil -> {:ok, Enum.map(results, fn {:ok, l} -> l end)}
        error -> error
      end
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{operation: operation, locations: locations}} ->
        {:ok, %{operation | locations: locations}}

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

  def change_operation_attachment(%OperationAttachment{} = attachment, attrs \\ %{}) do
    OperationAttachment.changeset(attachment, attrs)
  end

  def create_operation_attachment(attrs) do
    %OperationAttachment{} |> OperationAttachment.changeset(attrs) |> Repo.insert()
  end

  def delete_operation_attachment(%OperationAttachment{} = attachment),
    do: Repo.delete(attachment)

  ## Attendance

  def list_attendance(operation_id) do
    OperationAttendance
    |> where([a], a.operation_id == ^operation_id)
    |> preload(:member)
    |> Repo.all()
  end

  def change_attendance(%OperationAttendance{} = attendance, attrs \\ %{}) do
    OperationAttendance.changeset(attendance, attrs)
  end

  @doc "Records attendance if one doesn't already exist for this operation/member pair."
  def record_attendance(operation_id, member_id, source, opts \\ []) do
    attrs = %{
      operation_id: operation_id,
      member_id: member_id,
      source: source,
      sighting_id: opts[:sighting_id],
      recorded_at: opts[:recorded_at] || DateTime.utc_now()
    }

    %OperationAttendance{}
    |> OperationAttendance.changeset(attrs)
    |> Repo.insert(
      on_conflict: :nothing,
      conflict_target: [:operation_id, :member_id]
    )
  end

  ## Geofence matching (§10)

  @doc """
  Finds the nearest active operation location whose operation window
  (`starts_at`..`ends_at`) contains `at` and whose `geofence_radius_m`
  contains `point`. Returns `{operation_location, operation}` or `nil`.
  """
  @spec match_location(Geo.Point.t(), DateTime.t()) ::
          {OperationLocation.t(), Operation.t()} | nil
  def match_location(%Geo.Point{} = point, %DateTime{} = at) do
    query =
      from l in OperationLocation,
        join: e in Operation,
        on: e.id == l.operation_id,
        where: e.starts_at <= ^at and e.ends_at >= ^at,
        where: fragment("ST_DWithin(?, ?, ?)", l.point, ^point, l.geofence_radius_m),
        order_by: fragment("ST_Distance(?, ?)", l.point, ^point),
        limit: 1,
        select: {l, e}

    Repo.one(query)
  end
end
