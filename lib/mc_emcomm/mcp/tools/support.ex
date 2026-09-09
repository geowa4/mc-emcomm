defmodule McEmcomm.MCP.Tools.Support do
  @moduledoc """
  Helpers shared by the tool modules: argument coercion, "not found" and
  "requires an approved member profile" answers, error formatting, and
  pagination. Imported by `use McEmcomm.MCP.Tool`.
  """

  alias McEmcomm.Accounts.Scope
  alias McEmcomm.MCP.Context
  alias McEmcomm.MCP.Cursor
  alias McEmcomm.Members.Member

  @doc """
  The caller's approved member profile, or an actionable error. Net logging,
  attendance, and the profile tools need a member record, which an admin
  account without one does not have (mirrors the web UI's refusals).
  """
  @spec approved_member(Context.t()) :: {:ok, Member.t()} | {:error, String.t()}
  def approved_member(%Context{scope: %Scope{member: %Member{status: :approved} = member}}),
    do: {:ok, member}

  def approved_member(_context),
    do:
      {:error,
       "This action needs an approved member profile. Your account is signed in but has no " <>
         "approved membership; an administrator can approve it at /admin/members."}

  @doc "Looks a record up with a non-raising getter, answering `not found` uniformly."
  @spec fetch(term(), (integer() -> struct() | nil), String.t()) ::
          {:ok, struct()} | {:error, String.t()}
  def fetch(id, getter, noun) when is_integer(id) do
    case getter.(id) do
      nil -> {:error, "#{noun} #{id} was not found."}
      record -> {:ok, record}
    end
  end

  def fetch(_id, _getter, noun), do: {:error, "#{noun} id must be an integer."}

  @doc "Paginates a list into `{key => page, next_cursor}`."
  @spec page([term()], String.t() | nil, String.t(), (term() -> map())) ::
          {:ok, map()} | {:error, String.t()}
  def page(items, cursor, key, presenter) do
    case Cursor.paginate(items, cursor) do
      {:ok, page, next} ->
        {:ok, %{key => Enum.map(page, presenter), "next_cursor" => next}}

      {:error, :invalid_cursor} ->
        {:error, "The cursor is not one this server issued; start again without a cursor."}
    end
  end

  @doc "Turns a context error into one actionable sentence."
  @spec format_error(term()) :: String.t()
  def format_error(message) when is_binary(message), do: message

  def format_error(%Ecto.Changeset{} = changeset) do
    errors =
      Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
        Regex.replace(~r"%{(\w+)}", message, fn _, key ->
          opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
        end)
      end)

    "Validation failed: " <>
      Enum.map_join(errors, "; ", fn {field, messages} ->
        "#{field} #{Enum.join(messages, ", ")}"
      end) <>
      "."
  end

  def format_error(:illegal_transition),
    do: "That status change is not allowed from the member's current status."

  def format_error(:not_approved), do: "Only approved members may do that."

  def format_error(:operation_ended),
    do: "RSVPs closed when the operation ended; mark attendance instead if you were there."

  def format_error(:has_started_net_sessions),
    do: "The member has started net sessions and cannot be deleted."

  def format_error(atom) when is_atom(atom), do: "The request failed: #{atom}."
  def format_error(other), do: "The request failed: #{inspect(other)}."

  @doc "Parses an ISO 8601 date-time argument into a `DateTime`."
  @spec parse_datetime(term(), String.t()) :: {:ok, DateTime.t()} | {:error, String.t()}
  def parse_datetime(value, field) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} ->
        {:ok, datetime}

      {:error, _} ->
        {:error, "#{field} must be an ISO 8601 date-time such as 2026-09-05T18:00:00Z."}
    end
  end

  def parse_datetime(nil, field), do: {:error, "#{field} is required."}
  def parse_datetime(_value, field), do: {:error, "#{field} must be a string."}

  @doc "Parses an ISO 8601 date argument into a `Date` (nil stays nil)."
  @spec parse_date(term(), String.t()) :: {:ok, Date.t() | nil} | {:error, String.t()}
  def parse_date(nil, _field), do: {:ok, nil}

  def parse_date(value, field) when is_binary(value) do
    case Date.from_iso8601(value) do
      {:ok, date} -> {:ok, date}
      {:error, _} -> {:error, "#{field} must be an ISO 8601 date such as 2026-09-05."}
    end
  end

  def parse_date(_value, field), do: {:error, "#{field} must be a string."}

  @doc "Builds a `%Geo.Point{}` from a `{lat, lng}` argument map."
  @spec to_point(map() | nil) :: Geo.Point.t() | nil
  def to_point(%{"lat" => lat, "lng" => lng}) when is_number(lat) and is_number(lng) do
    %Geo.Point{coordinates: {lng / 1, lat / 1}, srid: 4326}
  end

  def to_point(_point), do: nil

  @doc "Copies the given argument keys (present ones only) into string-keyed attrs."
  @spec take_attrs(map(), [String.t()]) :: map()
  def take_attrs(args, keys), do: Map.take(args, keys)
end
