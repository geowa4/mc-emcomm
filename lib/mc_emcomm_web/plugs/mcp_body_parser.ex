defmodule McEmcommWeb.Plugs.MCPBodyParser do
  @moduledoc """
  A `Plug.Parsers` parser for `POST /mcp` only. JSON-RPC wants a malformed
  body answered with a `-32700` *JSON-RPC* error, whereas `Plug.Parsers.JSON`
  raises and produces the app's generic 400. This parser runs ahead of it in
  the endpoint, decodes the body itself, and hands the outcome to
  `McEmcommWeb.MCP.Transport` in `conn.assigns.mcp_message` as
  `{:ok, term}` or `{:error, :parse}`. Every other path falls through.

  Size limits and the body reader are the ones `Plug.Parsers` is configured
  with, so an oversized body still becomes a 413.
  """
  @behaviour Plug.Parsers

  @impl Plug.Parsers
  def init(opts), do: opts

  @impl Plug.Parsers
  def parse(%Plug.Conn{path_info: ["mcp"]} = conn, "application", "json", _params, opts) do
    {{mod, fun, args}, opts} = Keyword.pop(opts, :body_reader, {Plug.Conn, :read_body, []})

    case apply(mod, fun, [conn, opts | args]) do
      {:ok, body, conn} -> {:ok, %{}, Plug.Conn.assign(conn, :mcp_message, decode(body))}
      {:more, _partial, conn} -> {:error, :too_large, conn}
      {:error, :timeout} -> raise Plug.TimeoutError
      {:error, _reason} -> raise Plug.BadRequestError
    end
  end

  def parse(conn, _type, _subtype, _params, _opts), do: {:next, conn}

  defp decode(body) do
    case Jason.decode(body) do
      {:ok, term} -> {:ok, term}
      {:error, _reason} -> {:error, :parse}
    end
  end
end
