defmodule MyAppWeb.Plugs.CacheRawBody do
  @moduledoc """
  `Plug.Parsers` body reader that keeps the raw request body in
  `conn.assigns.raw_body` (as a reversed list of chunks) for HMAC
  verification of inbound webhooks. Only webhook requests are captured.

  A body larger than the reader's `:length` arrives over several
  `{:more, chunk, conn}` reads, which is why the chunks are accumulated
  rather than replaced.
  """

  @webhook_prefix "webhooks"

  @type read_result ::
          {:ok, binary(), Plug.Conn.t()}
          | {:more, binary(), Plug.Conn.t()}
          | {:error, term()}

  @spec read_body(Plug.Conn.t(), keyword()) :: read_result()
  def read_body(%Plug.Conn{path_info: [@webhook_prefix | _]} = conn, opts) do
    case Plug.Conn.read_body(conn, opts) do
      {:ok, body, conn} -> {:ok, body, cache_chunk(conn, body)}
      {:more, body, conn} -> {:more, body, cache_chunk(conn, body)}
      {:error, reason} -> {:error, reason}
    end
  end

  def read_body(conn, opts), do: Plug.Conn.read_body(conn, opts)

  defp cache_chunk(conn, body) do
    update_in(conn.assigns[:raw_body], fn chunks -> [body | chunks || []] end)
  end
end
