defmodule McEmcomm.MCP.Protocol do
  @moduledoc """
  The wire-level rules of MCP revision 2026-07-28 (SPEC.md §28): JSON-RPC 2.0
  envelope parsing, the request-metadata headers and `_meta` fields the
  Streamable HTTP transport requires, result and error construction, and
  `server/discover`.

  This server speaks the stateless revision only. There is no `initialize`
  handshake, no session id, no `ping`, and no SSE; a client that presents any
  other protocol version is told which versions are supported
  (`UnsupportedProtocolVersion`, `-32022`) and is not served.
  """

  @protocol_version "2026-07-28"
  @supported_versions [@protocol_version]

  @meta_protocol_version "io.modelcontextprotocol/protocolVersion"
  @meta_client_info "io.modelcontextprotocol/clientInfo"
  @meta_client_capabilities "io.modelcontextprotocol/clientCapabilities"
  @meta_server_info "io.modelcontextprotocol/serverInfo"
  @trace_keys ~w(traceparent tracestate baggage)

  # JSON-RPC 2.0 and MCP error codes.
  @parse_error -32_700
  @invalid_request -32_600
  @method_not_found -32_601
  @invalid_params -32_602
  @internal_error -32_603
  @header_mismatch -32_020
  @unsupported_protocol_version -32_022

  @base64_prefix "=?base64?"
  @base64_suffix "?="

  @type request_id :: String.t() | integer()
  @type message ::
          {:request, request_id(), String.t(), map()}
          | {:notification, String.t(), map()}
  @type rpc_error :: {:error, integer(), String.t(), map() | nil}

  def protocol_version, do: @protocol_version
  def supported_versions, do: @supported_versions

  def parse_error, do: @parse_error
  def invalid_request, do: @invalid_request
  def method_not_found, do: @method_not_found
  def invalid_params, do: @invalid_params
  def internal_error, do: @internal_error
  def header_mismatch, do: @header_mismatch
  def unsupported_protocol_version, do: @unsupported_protocol_version

  @doc "The HTTP status that accompanies a JSON-RPC error response."
  @spec http_status(integer()) :: pos_integer()
  def http_status(@method_not_found), do: 404
  def http_status(@internal_error), do: 500
  def http_status(_code), do: 400

  ## Envelope

  @doc """
  Classifies one decoded JSON body as a request or a notification. Batches,
  responses, and anything that is not a JSON-RPC 2.0 message are rejected
  with `-32600`; the request id must be a string or integer, never null.
  """
  @spec decode(term()) :: message() | rpc_error()
  def decode(%{"jsonrpc" => "2.0", "method" => method} = msg) when is_binary(method) do
    params = params_of(msg["params"])

    cond do
      is_nil(params) ->
        {:error, @invalid_request, "params must be an object", nil}

      Map.has_key?(msg, "id") and valid_id?(msg["id"]) ->
        {:request, msg["id"], method, params}

      Map.has_key?(msg, "id") ->
        {:error, @invalid_request, "id must be a string or integer", nil}

      true ->
        {:notification, method, params}
    end
  end

  def decode(list) when is_list(list),
    do: {:error, @invalid_request, "JSON-RPC batching is not supported", nil}

  def decode(%{"jsonrpc" => "2.0"} = msg)
      when is_map_key(msg, :result) or is_map_key(msg, "result") or is_map_key(msg, "error"),
      do: {:error, @invalid_request, "clients must not send JSON-RPC responses", nil}

  def decode(_other), do: {:error, @invalid_request, "not a JSON-RPC 2.0 message", nil}

  defp params_of(nil), do: %{}
  defp params_of(params) when is_map(params), do: params
  defp params_of(_params), do: nil

  defp valid_id?(id) when is_binary(id) or is_integer(id), do: true
  defp valid_id?(_id), do: false

  ## Headers and _meta

  @doc """
  Checks the request-metadata headers against the body of a request.

    * `MCP-Protocol-Version` absent or not `2026-07-28` → `-32022`, with
      `data.supported` naming this server's versions. A missing header is
      treated as an unsupported (legacy) version rather than as a header
      mismatch so that a pre-2026 client gets the one diagnostic it can act
      on.
    * `_meta["io.modelcontextprotocol/protocolVersion"]` absent → `-32602`;
      present but different from the header → `-32020`.
    * `Mcp-Method` absent or different from `method` → `-32020`.
    * `Mcp-Name` absent or different from `params.name` on `tools/call` →
      `-32020` (the Base64 sentinel encoding is decoded first).

  `headers` is a map of lower-cased header names to their first value.
  """
  @spec validate_headers(%{String.t() => String.t()}, String.t(), map()) :: :ok | rpc_error()
  def validate_headers(headers, method, params) do
    with :ok <- check_protocol_version(headers["mcp-protocol-version"]),
         :ok <- check_meta_version(params["_meta"], headers["mcp-protocol-version"]),
         :ok <- check_method_header(headers["mcp-method"], method) do
      check_name_header(headers["mcp-name"], method, params)
    end
  end

  defp check_protocol_version(@protocol_version), do: :ok

  defp check_protocol_version(requested) do
    {:error, @unsupported_protocol_version, "Unsupported protocol version",
     %{
       "supported" => @supported_versions,
       "supportedVersions" => @supported_versions,
       "requested" => requested
     }}
  end

  defp check_meta_version(%{@meta_protocol_version => version}, header) when is_binary(version) do
    if version == header do
      :ok
    else
      {:error, @header_mismatch,
       "Header mismatch: MCP-Protocol-Version header value '#{header}' does not match " <>
         "_meta protocol version '#{version}'", nil}
    end
  end

  defp check_meta_version(_meta, _header) do
    {:error, @invalid_params,
     "Invalid params: params._meta[\"#{@meta_protocol_version}\"] is required", nil}
  end

  defp check_method_header(nil, _method),
    do: {:error, @header_mismatch, "Header mismatch: Mcp-Method header is required", nil}

  defp check_method_header(header, method) when header == method, do: :ok

  defp check_method_header(header, method) do
    {:error, @header_mismatch,
     "Header mismatch: Mcp-Method header value '#{header}' does not match body method '#{method}'",
     nil}
  end

  defp check_name_header(header, "tools/call", params) do
    name = params["name"]

    case decode_header_value(header) do
      :missing ->
        {:error, @header_mismatch, "Header mismatch: Mcp-Name header is required for tools/call",
         nil}

      :invalid ->
        {:error, @header_mismatch, "Header mismatch: Mcp-Name header is not decodable", nil}

      {:ok, value} when value == name ->
        :ok

      {:ok, value} ->
        {:error, @header_mismatch,
         "Header mismatch: Mcp-Name header value '#{value}' does not match body value " <>
           "'#{inspect(name)}'", nil}
    end
  end

  defp check_name_header(_header, _method, _params), do: :ok

  @doc "Decodes a header value that may use the `=?base64?…?=` sentinel encoding."
  @spec decode_header_value(String.t() | nil) :: {:ok, String.t()} | :missing | :invalid
  def decode_header_value(nil), do: :missing

  def decode_header_value(@base64_prefix <> rest) do
    with true <- String.ends_with?(rest, @base64_suffix),
         encoded = String.trim_trailing(rest, @base64_suffix),
         {:ok, decoded} <- Base.decode64(encoded, padding: true) do
      {:ok, decoded}
    else
      _ -> :invalid
    end
  end

  def decode_header_value(value) when is_binary(value), do: {:ok, value}

  @doc "The client's self-reported name and version from `_meta`, for logging only."
  @spec client_info(map()) :: %{name: String.t() | nil, version: String.t() | nil}
  def client_info(params) do
    case get_in(params, ["_meta", @meta_client_info]) do
      %{} = info -> %{name: string(info["name"]), version: string(info["version"])}
      _ -> %{name: nil, version: nil}
    end
  end

  defp string(value) when is_binary(value), do: String.slice(value, 0, 120)
  defp string(_value), do: nil

  @doc "The client capabilities declared for this request (an empty map when absent)."
  @spec client_capabilities(map()) :: map()
  def client_capabilities(params) do
    case get_in(params, ["_meta", @meta_client_capabilities]) do
      %{} = caps -> caps
      _ -> %{}
    end
  end

  @doc "The W3C trace-context entries carried in `_meta`, as a text-map carrier."
  @spec trace_carrier(map()) :: [{String.t(), String.t()}]
  def trace_carrier(params) do
    meta = params["_meta"] || %{}

    for key <- @trace_keys, is_binary(meta[key]), do: {key, meta[key]}
  end

  ## Results

  @doc "The server's identity, attached to every result."
  @spec server_info() :: map()
  def server_info do
    %{
      "name" => "mc_emcomm",
      "title" => "Monroe County ARES/RACES",
      "version" => Application.get_env(:mc_emcomm, :git_sha, "unknown")
    }
  end

  @doc "Wraps a payload as a complete result carrying `serverInfo` in `_meta`."
  @spec result(map()) :: map()
  def result(payload) when is_map(payload) do
    payload
    |> Map.put("resultType", "complete")
    |> Map.update("_meta", %{@meta_server_info => server_info()}, fn meta ->
      Map.put(meta || %{}, @meta_server_info, server_info())
    end)
  end

  @doc "The `server/discover` result."
  @spec discover_result() :: map()
  def discover_result do
    result(%{
      "supportedVersions" => @supported_versions,
      "capabilities" => %{"tools" => %{}},
      "instructions" => instructions(),
      "ttlMs" => 3_600_000,
      "cacheScope" => "public"
    })
  end

  defp instructions do
    "Monroe County ARES/RACES member portal. Tools act as the signed-in member and are " <>
      "limited to what that member may do on the website: any approved member can run nets " <>
      "and read operations, equipment, and catalogs; administrators can also manage members, " <>
      "operations, and catalogs. Ids returned by list tools are the ids other tools expect."
  end

  @doc "A JSON-RPC success response."
  @spec response(request_id(), map()) :: map()
  def response(id, result), do: %{"jsonrpc" => "2.0", "id" => id, "result" => result}

  @doc "A JSON-RPC error response; `id` is `nil` when the request id could not be read."
  @spec error_response(request_id() | nil, integer(), String.t(), map() | nil) :: map()
  def error_response(id, code, message, data \\ nil) do
    error = %{"code" => code, "message" => message}
    error = if data, do: Map.put(error, "data", data), else: error
    %{"jsonrpc" => "2.0", "id" => id, "error" => error}
  end
end
