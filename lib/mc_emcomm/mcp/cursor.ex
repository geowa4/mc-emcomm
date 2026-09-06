defmodule McEmcomm.MCP.Cursor do
  @moduledoc """
  Opaque pagination cursors for `tools/list` and the list tools. A cursor
  encodes an offset into a deterministically ordered list; clients treat it
  as an opaque token (SPEC.md §28), and an unparseable one is rejected.
  """

  @page_size 50

  @doc "Items per page."
  @spec page_size() :: pos_integer()
  def page_size, do: @page_size

  @doc """
  Slices `items` at the page named by `cursor` (nil for the first page).
  Returns the page and the cursor for the next one, or `nil` at the end.
  """
  @spec paginate([term()], String.t() | nil, pos_integer()) ::
          {:ok, [term()], String.t() | nil} | {:error, :invalid_cursor}
  def paginate(items, cursor, page_size \\ @page_size) when is_list(items) do
    with {:ok, offset} <- decode(cursor) do
      page = items |> Enum.drop(offset) |> Enum.take(page_size)
      next = offset + page_size
      {:ok, page, if(next < length(items), do: encode(next), else: nil)}
    end
  end

  @doc false
  @spec encode(non_neg_integer()) :: String.t()
  def encode(offset) when is_integer(offset) and offset >= 0 do
    Base.url_encode64("offset:#{offset}", padding: false)
  end

  @doc false
  @spec decode(term()) :: {:ok, non_neg_integer()} | {:error, :invalid_cursor}
  def decode(nil), do: {:ok, 0}

  def decode(cursor) when is_binary(cursor) do
    with {:ok, "offset:" <> digits} <- Base.url_decode64(cursor, padding: false),
         {offset, ""} when offset >= 0 <- Integer.parse(digits) do
      {:ok, offset}
    else
      _ -> {:error, :invalid_cursor}
    end
  end

  def decode(_cursor), do: {:error, :invalid_cursor}
end
