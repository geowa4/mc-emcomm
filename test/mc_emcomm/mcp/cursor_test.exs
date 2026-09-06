defmodule McEmcomm.MCP.CursorTest do
  use ExUnit.Case, async: true

  alias McEmcomm.MCP.Cursor

  test "pages a list with opaque cursors and ends with nil" do
    items = Enum.to_list(1..5)
    assert {:ok, [1, 2], cursor} = Cursor.paginate(items, nil, 2)
    assert is_binary(cursor)
    assert {:ok, [3, 4], cursor} = Cursor.paginate(items, cursor, 2)
    assert {:ok, [5], nil} = Cursor.paginate(items, cursor, 2)
  end

  test "an exact multiple ends without an empty extra page" do
    assert {:ok, [1, 2], nil} = Cursor.paginate([1, 2], nil, 2)
  end

  test "cursors this server did not issue are rejected" do
    assert Cursor.paginate([1], "not-a-cursor", 2) == {:error, :invalid_cursor}

    assert Cursor.paginate([1], Base.url_encode64("offset:-1", padding: false), 2) ==
             {:error, :invalid_cursor}

    assert Cursor.paginate([1], 42, 2) == {:error, :invalid_cursor}
  end
end
