defmodule McEmcomm.MCP.Tool do
  @moduledoc """
  The behaviour every MCP tool implements (SPEC.md §28).

  A tool is a thin adapter: it declares its wire description (name, title,
  description, JSON schemas, annotations), the OAuth scope a token must
  carry, and the tier the caller's *live* role must have, and `run/2` calls
  the existing context functions as the authenticated user. Tools never
  duplicate business logic or authorization; they translate between the MCP
  argument map and the contexts, and between context results and
  `structuredContent`.

  Naming: `snake_case`, domain-prefixed where it disambiguates, at most 30
  characters. Read and write operations are always separate tools.
  """

  alias McEmcomm.MCP.Context

  @type result :: {:ok, map()} | {:error, String.t() | Ecto.Changeset.t() | atom()}

  @callback name() :: String.t()
  @callback title() :: String.t()
  @callback description() :: String.t()
  @callback input_schema() :: map()
  @callback output_schema() :: map()
  @callback annotations() :: map()
  @callback required_scope() :: String.t()
  @callback required_role() :: :member | :admin
  @callback run(args :: map(), Context.t()) :: result()

  @doc false
  defmacro __using__(_opts) do
    quote do
      @behaviour McEmcomm.MCP.Tool

      import McEmcomm.MCP.Tools.Support

      alias McEmcomm.MCP.Context
      alias McEmcomm.MCP.Schemas
    end
  end

  @doc "The tool's entry in a `tools/list` result."
  @spec definition(module()) :: map()
  def definition(module) do
    %{
      "name" => module.name(),
      "title" => module.title(),
      "description" => module.description(),
      "inputSchema" => module.input_schema(),
      "outputSchema" => module.output_schema(),
      "annotations" => Map.put(module.annotations(), "title", module.title())
    }
  end

  @doc "Annotations for a tool that only reads."
  @spec read_only() :: map()
  def read_only,
    do: %{
      "readOnlyHint" => true,
      "destructiveHint" => false,
      "idempotentHint" => true,
      "openWorldHint" => false
    }

  @doc "Annotations for a tool that creates or updates without destroying."
  @spec write(keyword()) :: map()
  def write(opts \\ []) do
    %{
      "readOnlyHint" => false,
      "destructiveHint" => Keyword.get(opts, :destructive, false),
      "idempotentHint" => Keyword.get(opts, :idempotent, false),
      "openWorldHint" => false
    }
  end
end
