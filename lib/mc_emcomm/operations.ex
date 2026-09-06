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
  alias McEmcomm.Storage

  ## Operations

  @doc """
  Lists operations, newest first. Options: `:visibility` keeps one visibility;
  `:active_at` keeps only operations whose `starts_at`..`ends_at` window
  contains the given `DateTime` (the ones a net may be assigned to).
  """
  def list_operations(opts \\ []) do
    Operation
    |> maybe_filter_visibility(opts[:visibility])
    |> maybe_filter_active_at(opts[:active_at])
    |> order_by([e], desc: e.starts_at)
    |> Repo.all()
  end

  defp maybe_filter_visibility(query, nil), do: query

  defp maybe_filter_visibility(query, visibility),
    do: where(query, [e], e.visibility == ^visibility)

  defp maybe_filter_active_at(query, nil), do: query

  defp maybe_filter_active_at(query, %DateTime{} = at),
    do: where(query, [e], e.starts_at <= ^at and e.ends_at >= ^at)

  @doc "Whether the operation's window contains `at` (defaults to now)."
  @spec active?(Operation.t(), DateTime.t()) :: boolean()
  def active?(%Operation{starts_at: starts_at, ends_at: ends_at}, at \\ DateTime.utc_now()) do
    DateTime.compare(starts_at, at) != :gt and DateTime.compare(ends_at, at) != :lt
  end

  @doc "Whether the operation with this id exists and is active at `at` (defaults to now)."
  @spec active_id?(term(), DateTime.t()) :: boolean()
  def active_id?(id, at \\ DateTime.utc_now()) do
    Operation
    |> where([e], e.id == ^id)
    |> maybe_filter_active_at(at)
    |> Repo.exists?()
  end

  def get_operation!(id) do
    Operation
    |> Repo.get!(id)
    |> Repo.preload([:locations, :attachments, attendance: :member])
  end

  @doc "Like `get_operation!/1` but `nil` for an unknown id."
  def get_operation(id) do
    case Repo.get(Operation, id) do
      nil -> nil
      operation -> Repo.preload(operation, [:locations, :attachments, attendance: :member])
    end
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

  @doc """
  Creates a new operation from `source`, carrying over its locations and
  attachments in one transaction. `attrs` supplies the new title, description,
  window, and visibility (the window is never copied). Each attachment's object
  is copied to a fresh key so the two operations never share storage, and the
  copies are recorded as uploaded by `uploaded_by_id`.
  """
  def copy_operation(%Operation{} = source, attrs, uploaded_by_id) do
    source = Repo.preload(source, [:locations, :attachments])

    Ecto.Multi.new()
    |> Ecto.Multi.insert(:operation, Operation.changeset(%Operation{}, attrs))
    |> Ecto.Multi.run(:locations, fn repo, %{operation: operation} ->
      insert_all_or_error(source.locations, fn location ->
        %OperationLocation{}
        |> OperationLocation.changeset(%{
          operation_id: operation.id,
          name: location.name,
          point: location.point,
          geofence_radius_m: location.geofence_radius_m,
          notes: location.notes,
          position: location.position
        })
        |> repo.insert()
      end)
    end)
    |> Ecto.Multi.run(:attachments, fn repo, %{operation: operation} ->
      insert_all_or_error(source.attachments, fn attachment ->
        key = Storage.build_key("operation-attachments", attachment.filename)
        :ok = Storage.copy_object(attachment.key, key)

        %OperationAttachment{}
        |> OperationAttachment.changeset(%{
          operation_id: operation.id,
          key: key,
          filename: attachment.filename,
          content_type: attachment.content_type,
          description: attachment.description,
          uploaded_by_id: uploaded_by_id
        })
        |> repo.insert()
      end)
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{operation: operation, locations: locations, attachments: attachments}} ->
        {:ok, %{operation | locations: locations, attachments: attachments}}

      {:error, _step, changeset, _} ->
        {:error, changeset}
    end
  end

  defp insert_all_or_error(items, insert) do
    Enum.reduce_while(items, {:ok, []}, fn item, {:ok, inserted} ->
      case insert.(item) do
        {:ok, record} -> {:cont, {:ok, [record | inserted]}}
        {:error, _} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, inserted} -> {:ok, Enum.reverse(inserted)}
      error -> error
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
