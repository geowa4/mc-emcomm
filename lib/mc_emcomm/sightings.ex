defmodule McEmcomm.Sightings do
  @moduledoc """
  The sighting-first QR flow (spec §9), recorded across three update points:

    * update point 0 — HTTP mount (disconnected render or a plug before it):
      `record_visit/1` creates the row from request metadata.
    * update point 1 — socket connect: `record_client_env/2` then, after the
      browser Geolocation prompt resolves, `record_geolocation/2`.
    * update point 2 — form submit: `submit/3` auto-links the member,
      geofence-matches an active exercise location, and records
      `exercise_attendance` for an approved member.

  Admin-only columns (identity/visit, client environment, geolocation) are
  gated at the query layer: `list_for_asset_member_view/1` selects only the
  submission fields members and admins may both see;
  `list_for_asset_admin_view/1` selects everything.
  """

  import Ecto.Query, warn: false

  alias McEmcomm.Exercises
  alias McEmcomm.Members
  alias McEmcomm.Repo
  alias McEmcomm.Sightings.Sighting

  ## Update point 0 — HTTP mount

  @spec record_visit(map()) :: {:ok, Sighting.t()} | {:error, Ecto.Changeset.t()}
  def record_visit(attrs) do
    %Sighting{}
    |> Sighting.visit_changeset(attrs)
    |> Repo.insert()
  end

  ## Update point 1 — socket connect

  def record_client_env(%Sighting{} = sighting, attrs) do
    sighting
    |> Sighting.client_env_changeset(attrs)
    |> Repo.update()
  end

  def record_geolocation(%Sighting{} = sighting, attrs) do
    sighting
    |> Sighting.geolocation_changeset(attrs)
    |> Repo.update()
  end

  ## Update point 2 — form submit

  @doc """
  Applies the sighting-form submission: links a member (by call sign, or the
  given `current_member` when the submitter is logged in), geofence-matches
  an active exercise location when the sighting captured a point, and — for
  an approved member matched to a location — records `exercise_attendance`
  with `source: :asset_checkin` carrying the `sighting_id`.
  """
  @spec submit(Sighting.t(), map(), keyword()) ::
          {:ok, Sighting.t()} | {:error, Ecto.Changeset.t()}
  def submit(%Sighting{} = sighting, attrs, opts \\ []) do
    current_member = opts[:current_member]
    now = DateTime.utc_now()

    call_sign = normalize_call_sign(attrs["call_sign"] || attrs[:call_sign])
    matched_member = current_member || member_by_call_sign(call_sign)

    {exercise_id, exercise_location_id} = geofence_match(sighting, now)

    submit_attrs =
      attrs
      |> Map.new(fn {k, v} -> {to_string(k), v} end)
      |> Map.put("submitted_at", now)
      |> Map.put("member_id", matched_member && matched_member.id)
      |> Map.put("exercise_id", exercise_id)
      |> Map.put("exercise_location_id", exercise_location_id)

    sighting
    |> Sighting.submit_changeset(submit_attrs)
    |> Repo.update()
    |> maybe_record_attendance(matched_member, exercise_id)
  end

  defp normalize_call_sign(nil), do: nil
  defp normalize_call_sign(""), do: nil
  defp normalize_call_sign(call_sign), do: call_sign |> String.trim() |> String.upcase()

  defp member_by_call_sign(nil), do: nil

  defp member_by_call_sign(call_sign) do
    Repo.get_by(McEmcomm.Members.Member, call_sign: call_sign, status: :approved)
  end

  defp geofence_match(%Sighting{point: %Geo.Point{}} = sighting, at) do
    case Exercises.match_location(sighting.point, at) do
      {location, exercise} -> {exercise.id, location.id}
      nil -> {nil, nil}
    end
  end

  defp geofence_match(_sighting, _at), do: {nil, nil}

  defp maybe_record_attendance(
         {:ok, sighting},
         %Members.Member{status: :approved} = member,
         exercise_id
       )
       when not is_nil(exercise_id) do
    Exercises.record_attendance(exercise_id, member.id, :asset_checkin,
      sighting_id: sighting.id,
      recorded_at: sighting.submitted_at
    )

    {:ok, sighting}
  end

  defp maybe_record_attendance(result, _member, _exercise_id), do: result

  ## Reads

  def get!(id), do: Repo.get!(Sighting, id)

  def get_by_session_token(token) do
    Repo.get_by(Sighting, session_token: token)
  end

  @doc "Admin-only mark of sighting legitimacy."
  def verify(%Sighting{} = sighting, verified) when is_boolean(verified) do
    sighting |> Ecto.Changeset.change(verified: verified) |> Repo.update()
  end

  @member_view_fields ~w(id asset_id submitted_at call_sign member_id claimed_responsibility
                          note verified exercise_id exercise_location_id inserted_at updated_at)a

  @doc "Member/admin-safe projection: excludes identity/visit, client-env, and geolocation columns."
  def list_for_asset_member_view(asset_id) do
    Sighting
    |> where([s], s.asset_id == ^asset_id and not is_nil(s.submitted_at))
    |> order_by([s], desc: s.submitted_at)
    |> select(^@member_view_fields)
    |> Repo.all()
  end

  @doc "Full projection, admin-only."
  def list_for_asset_admin_view(asset_id) do
    Sighting
    |> where([s], s.asset_id == ^asset_id)
    |> order_by([s], desc: s.visited_at)
    |> Repo.all()
  end

  ## Retention (§20)

  @doc "Scrubs raw telemetry from sightings visited before `cutoff`, setting `scrubbed_at`."
  def scrub_before(%DateTime{} = cutoff) do
    Sighting
    |> where([s], s.visited_at < ^cutoff and is_nil(s.scrubbed_at))
    |> Repo.all()
    |> Enum.each(fn sighting ->
      sighting |> Sighting.scrub_changeset() |> Repo.update()
    end)
  end
end
