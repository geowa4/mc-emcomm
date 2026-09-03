defmodule McEmcomm.Sightings do
  @moduledoc """
  The sighting-first QR flow (spec §9), recorded across three update points:

    * update point 0 — HTTP mount (disconnected render or a plug before it):
      `record_visit/1` creates the row from request metadata.
    * update point 1 — socket connect: `record_client_env/2` then, after the
      browser Geolocation prompt resolves, `record_geolocation/2`.
    * update point 2 — form submit: `submit/3` auto-links the member,
      geofence-matches an active operation location, and records
      `operation_attendance` for an approved member.

  Admin-only columns (identity/visit, client environment, geolocation) are
  gated at the query layer: `list_for_asset_member_view/1` selects only the
  submission fields members and admins may both see;
  `list_for_asset_admin_view/1` selects everything.
  """

  import Ecto.Query, warn: false

  alias McEmcomm.Members
  alias McEmcomm.Operations
  alias McEmcomm.Repo
  alias McEmcomm.Sightings.Sighting

  ## Update point 0 — HTTP mount

  # Tokens that nearly every crawler, indexer, and link-preview fetcher
  # announces. UAInspector's bot database is the authority when it has been
  # downloaded; this list stands in when it hasn't and catches the common
  # cases either way.
  @crawler_pattern ~r/bot|crawl|spider|slurp|fetch|preview|scan|facebookexternalhit/i

  @doc """
  Whether a user-agent string belongs to a crawler, indexer, or link-preview
  fetcher rather than a person's browser.
  """
  @spec crawler_user_agent?(String.t()) :: boolean()
  def crawler_user_agent?(user_agent) when is_binary(user_agent) do
    Regex.match?(@crawler_pattern, user_agent) or UAInspector.bot?(user_agent)
  end

  @spec record_visit(map()) :: {:ok, Sighting.t()} | {:error, Ecto.Changeset.t()}
  def record_visit(attrs) do
    %Sighting{}
    |> Sighting.visit_changeset(Map.merge(attrs, parse_user_agent(attrs)))
    |> Repo.insert()
  end

  # Derives browser/OS/device columns from the raw user-agent and client-hint
  # headers. UAInspector reads its databases from ETS; when they haven't been
  # downloaded (`mix ua_inspector.download`) every lookup comes back :unknown
  # and the columns stay nil rather than erroring.
  defp parse_user_agent(attrs) do
    hints =
      [
        {"sec-ch-ua", attrs[:sec_ch_ua]},
        {"sec-ch-ua-platform", attrs[:sec_ch_ua_platform]},
        {"sec-ch-ua-mobile", attrs[:sec_ch_ua_mobile]}
      ]
      |> Enum.reject(fn {_header, value} -> is_nil(value) end)

    client_hints = if hints == [], do: nil, else: UAInspector.ClientHints.new(hints)

    case UAInspector.parse(attrs[:user_agent], client_hints) do
      %UAInspector.Result{client: client, os: os, device: device} ->
        %{
          browser_name: known(client, :name),
          browser_version: known(client, :version),
          os_name: known(os, :name),
          os_version: known(os, :version),
          device_type: known(device, :type)
        }

      %UAInspector.Result.Bot{name: name} ->
        %{browser_name: known_value(name), device_type: "bot"}
    end
  end

  defp known(:unknown, _key), do: nil
  defp known(struct, key), do: struct |> Map.get(key) |> known_value()

  defp known_value(:unknown), do: nil
  defp known_value(value), do: value

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

  # The only fields the sighting form itself owns; see `submit/3`.
  @submitter_fields ~w(call_sign note claimed_responsibility)

  @doc """
  Applies the sighting-form submission: links a member (by call sign, or the
  given `current_member` when the submitter is logged in), geofence-matches
  an active operation location when the sighting captured a point, and — for
  an approved member matched to a location — records `operation_attendance`
  with `source: :asset_checkin` carrying the `sighting_id`.
  """
  @spec submit(Sighting.t(), map(), keyword()) ::
          {:ok, Sighting.t()} | {:error, Ecto.Changeset.t()}
  def submit(%Sighting{} = sighting, attrs, opts \\ []) do
    current_member = opts[:current_member]
    now = DateTime.utc_now()

    call_sign = normalize_call_sign(attrs["call_sign"] || attrs[:call_sign])
    matched_member = current_member || member_by_call_sign(call_sign)

    {operation_id, operation_location_id} = geofence_match(sighting, now)

    submit_attrs =
      attrs
      |> Map.new(fn {k, v} -> {to_string(k), v} end)
      # `attrs` is the submitter's own form payload, which a client can shape
      # freely over the socket. Only the three fields the form owns survive;
      # everything else on the sighting is resolved here or is admin-only.
      |> Map.take(@submitter_fields)
      |> Map.merge(%{
        "submitted_at" => now,
        "member_id" => matched_member && matched_member.id,
        "operation_id" => operation_id,
        "operation_location_id" => operation_location_id
      })

    sighting
    |> Sighting.submit_changeset(submit_attrs)
    |> Repo.update()
    |> maybe_record_attendance(matched_member, operation_id)
  end

  defp normalize_call_sign(nil), do: nil
  defp normalize_call_sign(""), do: nil
  defp normalize_call_sign(call_sign), do: call_sign |> String.trim() |> String.upcase()

  defp member_by_call_sign(nil), do: nil

  defp member_by_call_sign(call_sign) do
    Repo.get_by(McEmcomm.Members.Member, call_sign: call_sign, status: :approved)
  end

  defp geofence_match(%Sighting{point: %Geo.Point{}} = sighting, at) do
    case Operations.match_location(sighting.point, at) do
      {location, operation} -> {operation.id, location.id}
      nil -> {nil, nil}
    end
  end

  defp geofence_match(_sighting, _at), do: {nil, nil}

  defp maybe_record_attendance(
         {:ok, sighting},
         %Members.Member{status: :approved} = member,
         operation_id
       )
       when not is_nil(operation_id) do
    Operations.record_attendance(operation_id, member.id, :asset_checkin,
      sighting_id: sighting.id,
      recorded_at: sighting.submitted_at
    )

    {:ok, sighting}
  end

  defp maybe_record_attendance(result, _member, _operation_id), do: result

  ## Reads

  def get!(id), do: Repo.get!(Sighting, id)

  @doc """
  The update-point-0 sighting for `asset_id`, looked up by the id and token
  `McEmcommWeb.Plugs.RecordSighting` put in the plug session.

  Returns nil unless both match: the token proves the session is the one the
  row was created for, and the `asset_id` check stops a session carried over
  from an earlier scan attaching a submission to a different asset.
  """
  @spec get_for_session(term(), term(), integer()) :: Sighting.t() | nil
  def get_for_session(id, token, asset_id) when is_integer(id) and is_binary(token) do
    with %Sighting{asset_id: ^asset_id} = sighting <- Repo.get(Sighting, id),
         true <- session_token_matches?(sighting, token) do
      sighting
    else
      _mismatch -> nil
    end
  end

  def get_for_session(_id, _token, _asset_id), do: nil

  defp session_token_matches?(%Sighting{session_token: stored}, token) when is_binary(stored) do
    Plug.Crypto.secure_compare(token, stored)
  end

  defp session_token_matches?(_sighting, _token), do: false

  def get_by_session_token(token) do
    Repo.get_by(Sighting, session_token: token)
  end

  @doc "Admin-only mark of sighting legitimacy."
  def verify(%Sighting{} = sighting, verified) when is_boolean(verified) do
    sighting |> Ecto.Changeset.change(verified: verified) |> Repo.update()
  end

  @member_view_fields ~w(id asset_id submitted_at call_sign member_id claimed_responsibility
                          note verified operation_id operation_location_id inserted_at updated_at)a

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

  @doc """
  Located sightings (those with a geolocation point) for the admin map,
  newest first. Options (mutually exclusive):

    * `limit: n` — only the n most recent
    * `since: %Date{}` — only those visited on or after that UTC date
  """
  def list_located_for_asset(asset_id, opts \\ []) do
    Sighting
    |> where([s], s.asset_id == ^asset_id and not is_nil(s.point))
    |> order_by([s], desc: s.visited_at)
    |> located_filter(opts)
    |> Repo.all()
  end

  defp located_filter(query, limit: n), do: limit(query, ^n)

  defp located_filter(query, since: %Date{} = date) do
    cutoff = DateTime.new!(date, ~T[00:00:00], "Etc/UTC")
    where(query, [s], s.visited_at >= ^cutoff)
  end

  defp located_filter(query, []), do: query

  @doc "UTC date of the asset's most recent located sighting, or nil."
  def last_seen_on(asset_id) do
    Sighting
    |> where([s], s.asset_id == ^asset_id and not is_nil(s.point))
    |> order_by([s], desc: s.visited_at)
    |> limit(1)
    |> select([s], s.visited_at)
    |> Repo.one()
    |> case do
      nil -> nil
      visited_at -> DateTime.to_date(visited_at)
    end
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
