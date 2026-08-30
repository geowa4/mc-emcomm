defmodule MyAppWeb.Plugs.CacheRawBodyTest do
  use ExUnit.Case, async: true

  import Plug.Test
  import Plug.Conn

  alias MyAppWeb.Plugs.CacheRawBody

  @parser_opts Plug.Parsers.init(
                 parsers: [:json],
                 pass: ["*/*"],
                 body_reader: {CacheRawBody, :read_body, []},
                 json_decoder: Jason
               )

  # `Plug.Conn.read_body/2` answers `{:more, chunk, conn}` when the body is
  # longer than `:length`. The reader has to hand that back so the parser can
  # turn it into a 413, rather than matching only on `{:ok, ...}`.
  @tiny_parser_opts Plug.Parsers.init(
                      parsers: [:json],
                      pass: ["*/*"],
                      body_reader: {CacheRawBody, :read_body, []},
                      json_decoder: Jason,
                      length: 16
                    )

  test "an oversized webhook body is rejected as too large" do
    body = ~s({"payload":") <> String.duplicate("a", 1_024) <> ~s("})

    assert_raise Plug.Parsers.RequestTooLargeError, fn ->
      :post
      |> conn("/webhooks/resend", body)
      |> put_req_header("content-type", "application/json")
      |> Plug.Parsers.call(@tiny_parser_opts)
    end
  end

  test "captures the raw body for webhook requests" do
    conn =
      :post
      |> conn("/webhooks/resend", ~s({"a":1}))
      |> put_req_header("content-type", "application/json")
      |> Plug.Parsers.call(@parser_opts)

    assert conn.body_params == %{"a" => 1}
    assert IO.iodata_to_binary(Enum.reverse(conn.assigns.raw_body)) == ~s({"a":1})
  end

  test "does not retain bodies for other requests" do
    conn =
      :post
      |> conn("/users/log-in", ~s({"a":1}))
      |> put_req_header("content-type", "application/json")
      |> Plug.Parsers.call(@parser_opts)

    assert conn.body_params == %{"a" => 1}
    refute Map.has_key?(conn.assigns, :raw_body)
  end
end

defmodule MyAppWeb.Plugs.CacheRawBodyErrorTest do
  use ExUnit.Case, async: true

  import Plug.Test

  alias MyAppWeb.Plugs.CacheRawBody

  test "a failed webhook body read is passed through untouched" do
    conn = %{conn(:post, "/webhooks/resend", "{}") | adapter: {MyAppWeb.FailingBodyAdapter, nil}}

    assert CacheRawBody.read_body(conn, []) == {:error, :timeout}
  end
end
