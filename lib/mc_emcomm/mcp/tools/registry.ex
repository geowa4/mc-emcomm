defmodule McEmcomm.MCP.Tools.Registry do
  @moduledoc """
  The ordered catalog of MCP tools and the `tools/call` pipeline: look the
  tool up, check the caller's live role, check the token's scope, validate
  the arguments against `inputSchema`, run the tool as the authenticated
  user, and validate `structuredContent` against `outputSchema`.

  The order of `@tools` is the order `tools/list` returns, so it is stable
  across requests (clients cache the list and LLM prompt caches key on it).
  """

  require Logger

  alias McEmcomm.Accounts.Scope
  alias McEmcomm.MCP.Context
  alias McEmcomm.MCP.Cursor
  alias McEmcomm.MCP.Schema
  alias McEmcomm.MCP.Tool
  alias McEmcomm.MCP.Tools

  @tools [
    # Net logger (emcomm:member)
    Tools.ListActiveNets,
    Tools.StartNet,
    Tools.AddCheckin,
    Tools.EndNet,
    Tools.ListNetCheckins,
    # Operations (emcomm:operations)
    Tools.ListOps,
    Tools.GetOp,
    Tools.CreateOp,
    Tools.UpdateOp,
    Tools.DeleteOp,
    Tools.AddOpLocation,
    Tools.RemoveOpLocation,
    Tools.ListOpAttendance,
    Tools.MarkOpAttendance,
    # Membership (emcomm:membership)
    Tools.ListPendingMembers,
    Tools.ApproveMember,
    Tools.TransitionMember,
    Tools.ListMembers,
    Tools.GetMember,
    # Profile (emcomm:member)
    Tools.GetMyProfile,
    Tools.UpdateMyProfile,
    # Equipment and catalogs (reads emcomm:member, writes emcomm:membership)
    Tools.ListAssets,
    Tools.GetAsset,
    Tools.CreateAsset,
    Tools.UpdateAsset,
    Tools.ListCatalog,
    Tools.CreateCatalogItem,
    Tools.UpdateCatalogItem,
    Tools.ListLocations,
    Tools.CreateLocation,
    Tools.UpdateLocation,
    Tools.ListDocuments
  ]

  @ttl_ms 300_000

  @doc "Every tool module, in list order."
  @spec all() :: [module()]
  def all, do: @tools

  @doc "Finds a tool by name."
  @spec fetch(term()) :: {:ok, module()} | :error
  def fetch(name) when is_binary(name) do
    case Enum.find(@tools, &(&1.name() == name)) do
      nil -> :error
      module -> {:ok, module}
    end
  end

  def fetch(_name), do: :error

  @doc "The `tools/list` result for a page."
  @spec list(String.t() | nil) :: {:ok, map()} | {:error, :invalid_cursor}
  def list(cursor) do
    with {:ok, page, next} <- Cursor.paginate(@tools, cursor) do
      result = %{
        "tools" => Enum.map(page, &Tool.definition/1),
        "ttlMs" => @ttl_ms,
        "cacheScope" => "public"
      }

      {:ok, if(next, do: Map.put(result, "nextCursor", next), else: result)}
    end
  end

  @doc """
  Runs `tools/call`. Protocol-level failures come back as `{:error, ...}`
  for the transport to map; everything the model could act on — a role the
  account lacks, invalid arguments, a business-rule refusal — is a normal
  `CallToolResult` with `isError: true` and an actionable message.
  """
  @spec call(term(), term(), Context.t()) ::
          {:ok, map()} | {:error, :unknown_tool} | {:error, {:insufficient_scope, String.t()}}
  def call(name, arguments, %Context{} = context) do
    with {:ok, module} <- fetch_tool(name),
         :ok <- check_scope(module, context) do
      {:ok, execute(module, arguments || %{}, context)}
    end
  end

  defp fetch_tool(name) do
    case fetch(name) do
      {:ok, module} -> {:ok, module}
      :error -> {:error, :unknown_tool}
    end
  end

  # A token missing a scope the role *could* hold is a step-up case (HTTP 403,
  # `insufficient_scope`); a scope the role can never hold is a tool error, so
  # the client does not loop through re-authorization it cannot satisfy.
  defp check_scope(module, %Context{scope: scope, scopes: granted}) do
    required = module.required_scope()

    cond do
      required in granted ->
        :ok

      McEmcomm.OAuth.Scopes.permitted?(scope, required) ->
        {:error, {:insufficient_scope, required}}

      true ->
        :ok
    end
  end

  defp execute(module, arguments, context) do
    :telemetry.span(
      [:mc_emcomm, :mcp, :tool],
      %{tool: module.name(), user_id: context.scope.user.id},
      fn ->
        result = run_checked(module, arguments, context)
        outcome = if result["isError"], do: :error, else: :ok
        {result, %{tool: module.name(), user_id: context.scope.user.id, outcome: outcome}}
      end
    )
  end

  defp run_checked(module, arguments, context) do
    with :ok <- check_role(module, context),
         :ok <- check_arguments(module, arguments) do
      run(module, arguments, context)
    else
      {:error, message} -> error_result(message)
    end
  end

  defp check_role(module, %Context{scope: scope}) do
    case module.required_role() do
      :admin ->
        if Scope.admin?(scope),
          do: :ok,
          else: {:error, "This tool requires an administrator account."}

      :member ->
        if Scope.approved_member?(scope) or Scope.admin?(scope),
          do: :ok,
          else: {:error, "This tool requires an approved member account."}
    end
  end

  defp check_arguments(module, arguments) when is_map(arguments) do
    case Schema.explain(module.input_schema(), arguments) do
      :ok -> :ok
      {:error, message} -> {:error, "Invalid arguments: #{message}."}
    end
  end

  defp check_arguments(_module, _arguments),
    do: {:error, "Invalid arguments: expected an object."}

  defp run(module, arguments, context) do
    case module.run(arguments, context) do
      {:ok, structured} when is_map(structured) -> success_result(module, structured)
      {:error, reason} -> error_result(Tools.Support.format_error(reason))
    end
  rescue
    exception ->
      Logger.error(
        "MCP tool #{module.name()} raised #{Exception.format(:error, exception, __STACKTRACE__)}"
      )

      error_result(
        "The #{module.name()} tool failed unexpectedly. Try again; if it keeps failing, " <>
          "tell an administrator what you were doing."
      )
  end

  defp success_result(module, structured) do
    case Schema.validate(module.output_schema(), structured) do
      :ok ->
        %{
          "content" => [%{"type" => "text", "text" => Jason.encode!(structured)}],
          "structuredContent" => structured,
          "isError" => false
        }

      {:error, errors} ->
        Logger.error("MCP tool #{module.name()} produced an invalid result: #{inspect(errors)}")

        error_result(
          "The #{module.name()} tool produced a result that failed its own output schema. " <>
            "This is a server bug; tell an administrator."
        )
    end
  end

  defp error_result(message) when is_binary(message) do
    %{"content" => [%{"type" => "text", "text" => message}], "isError" => true}
  end
end
