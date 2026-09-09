defmodule McEmcomm.OAuth.Scopes do
  @moduledoc """
  The three OAuth scopes the MCP connector issues (SPEC.md §28) and their
  mapping onto the app's tiers (§3).

  A scope is an *area* of the API; the user's tier decides whether they may
  hold it at all. A token never carries a scope the user's live role does
  not permit: `effective/2` intersects the requested set with
  `permitted_for/1` at issuance and again on every refresh, and each
  `tools/call` re-checks the live role on top of the scope.
  """

  alias McEmcomm.Accounts.Scope

  @member "emcomm:member"
  @operations "emcomm:operations"
  @membership "emcomm:membership"

  @all [@member, @operations, @membership]

  @descriptions %{
    @member =>
      "Run and log nets, view and edit your own profile, and read the equipment " <>
        "inventory and training catalogs.",
    @operations =>
      "Read operations and their locations, attachments, RSVPs, and attendance, " <>
        "RSVP, and mark your own attendance. Administrators may also create and " <>
        "edit operations.",
    @membership =>
      "Administration: approve and manage members and maintain the catalogs of " <>
        "equipment, capabilities, courses, certifications, and locations."
  }

  @doc "Every scope, in canonical order."
  @spec all() :: [String.t()]
  def all, do: @all

  def member, do: @member
  def operations, do: @operations
  def membership, do: @membership

  @doc "A one-sentence description of a scope, for the consent screen."
  @spec description(String.t()) :: String.t()
  def description(scope), do: Map.fetch!(@descriptions, scope)

  @doc "Whether the string names a scope this server issues."
  @spec valid?(term()) :: boolean()
  def valid?(scope), do: scope in @all

  @doc """
  The scopes a user's live role may hold: approved members and admins get
  member and operations, admins additionally get membership. Anyone else —
  pending, rejected, or inactive members and users with no profile — gets
  nothing.
  """
  @spec permitted_for(Scope.t() | nil) :: [String.t()]
  def permitted_for(%Scope{} = scope) do
    cond do
      Scope.admin?(scope) -> @all
      Scope.approved_member?(scope) -> [@member, @operations]
      true -> []
    end
  end

  def permitted_for(nil), do: []

  @doc "Whether the role permits the scope at all (as opposed to the token carrying it)."
  @spec permitted?(Scope.t() | nil, String.t()) :: boolean()
  def permitted?(scope, requested), do: requested in permitted_for(scope)

  @doc """
  The scopes to issue: the requested set intersected with what the role
  permits, in canonical order. An empty request means "everything the role
  permits".
  """
  @spec effective([String.t()], Scope.t() | nil) :: [String.t()]
  def effective([], scope), do: permitted_for(scope)

  def effective(requested, scope) when is_list(requested) do
    permitted = permitted_for(scope)
    Enum.filter(@all, &(&1 in requested and &1 in permitted))
  end

  @doc """
  Parses a space-delimited `scope` parameter. `nil` or blank means "no
  preference" (`{:ok, []}`); an unknown scope is `{:error, :invalid_scope}`.
  """
  @spec parse(String.t() | nil) :: {:ok, [String.t()]} | {:error, :invalid_scope}
  def parse(nil), do: {:ok, []}

  def parse(scope) when is_binary(scope) do
    requested = scope |> String.split(" ", trim: true) |> Enum.uniq()

    if Enum.all?(requested, &valid?/1) do
      {:ok, Enum.filter(@all, &(&1 in requested))}
    else
      {:error, :invalid_scope}
    end
  end

  def parse(_scope), do: {:error, :invalid_scope}

  @doc "Formats scopes as the space-delimited `scope` parameter."
  @spec join([String.t()]) :: String.t()
  def join(scopes), do: Enum.join(scopes, " ")
end
