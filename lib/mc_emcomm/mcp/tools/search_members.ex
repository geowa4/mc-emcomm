defmodule McEmcomm.MCP.Tools.SearchMembers do
  @moduledoc false
  use McEmcomm.MCP.Tool

  alias McEmcomm.Accounts.Scope
  alias McEmcomm.MCP.Cursor
  alias McEmcomm.MCP.Tool
  alias McEmcomm.MCP.Tools.Present
  alias McEmcomm.Members
  alias McEmcomm.OAuth.Scopes

  @sorts %{"name" => :name, "call_sign" => :call_sign}

  @impl true
  def name, do: "search_members"
  @impl true
  def title, do: "Search the member directory"

  @impl true
  def description,
    do:
      "Searches the member directory by name, call sign, or email and returns each member's name, " <>
        "call sign, email, license class, positions, and home location. The directory can be " <>
        "long: pass query to narrow it rather than paging through everyone. Lists approved " <>
        "members; administrators may pass status to list pending, rejected, or inactive ones."

  @impl true
  def input_schema do
    Schemas.object(%{
      "query" =>
        Schemas.string(
          "Letters the name, call sign, or email must contain, case-insensitively. " <>
            "Omit to list everyone.",
          max: 100
        ),
      "sort" => Schemas.string("Order of the results; name by default.", enum: Map.keys(@sorts)),
      "status" =>
        Schemas.string(
          "Membership status to list; approved by default. Any other status is for " <>
            "administrators only.",
          enum: ~w(pending approved rejected inactive)
        ),
      "cursor" => Schemas.cursor()
    })
  end

  @impl true
  def output_schema, do: Schemas.directory_page()
  @impl true
  def annotations, do: Tool.read_only()
  @impl true
  def required_scope, do: Scopes.member()
  @impl true
  def required_role, do: :member

  @impl true
  def run(args, context) do
    with {:ok, status} <- status(args["status"], context),
         {:ok, page} <- page_number(args["cursor"]) do
      directory =
        Members.list_directory(
          search: args["query"],
          sort: Map.get(@sorts, args["sort"]),
          status: status,
          page: page,
          per_page: Cursor.page_size()
        )

      {:ok,
       %{
         "members" => Enum.map(entries(directory, page), &Present.directory_member/1),
         "total_count" => directory.total_count,
         "next_cursor" => next_cursor(directory, page)
       }}
    end
  end

  # The directory itself is approved members. The other statuses are the
  # administrators' membership records, which a token reaches only with the
  # membership scope (as `get_member` does).
  defp status(status, _context) when status in [nil, "approved"], do: {:ok, :approved}

  defp status(status, %Context{scope: scope, scopes: scopes}) do
    if Scope.admin?(scope) and Scopes.membership() in scopes do
      {:ok, String.to_existing_atom(status)}
    else
      {:error,
       "Only administrators, with the #{Scopes.membership()} scope, may list #{status} " <>
         "members. Leave status out to search approved members."}
    end
  end

  defp page_number(cursor) do
    size = Cursor.page_size()

    case Cursor.decode(cursor) do
      {:ok, offset} when rem(offset, size) == 0 ->
        {:ok, div(offset, size) + 1}

      _invalid ->
        {:error, "The cursor is not one this server issued; start again without a cursor."}
    end
  end

  # The context answers a page past the end with the last page; a cursor
  # that points there has simply run out of members.
  defp entries(%{page: page, entries: entries}, page), do: entries
  defp entries(_directory, _page), do: []

  defp next_cursor(%{total_pages: total_pages}, page) when page < total_pages,
    do: Cursor.encode(page * Cursor.page_size())

  defp next_cursor(_directory, _page), do: nil
end
