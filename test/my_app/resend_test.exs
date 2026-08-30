defmodule MyApp.ResendTest do
  use ExUnit.Case, async: true

  import MyApp.ResendHelpers

  alias MyApp.Resend

  describe "list_received/1" do
    test "sends the bearer token and query params" do
      Req.Test.stub(Resend, fn conn ->
        assert Plug.Conn.get_req_header(conn, "authorization") == ["Bearer re_test_key"]
        assert conn.request_path == "/emails/receiving"
        assert conn.query_params == %{"limit" => "5", "after" => "em_1"}
        Req.Test.json(conn, %{"object" => "list", "has_more" => false, "data" => []})
      end)

      assert {:ok, [], false} = Resend.list_received(limit: 5, after: "em_1")
    end

    test "reports a 200 whose body carries no data list" do
      Req.Test.stub(Resend, fn conn -> Req.Test.json(conn, %{"object" => "list"}) end)
      assert {:error, :unexpected_body} = Resend.list_received()
    end

    test "reports unexpected statuses" do
      Req.Test.stub(Resend, fn conn ->
        conn |> Plug.Conn.put_status(401) |> Req.Test.json(%{"message" => "nope"})
      end)

      assert {:error, {:unexpected_status, 401}} = Resend.list_received()
    end

    test "reports transport errors" do
      Req.Test.stub(Resend, fn conn -> Req.Test.transport_error(conn, :econnrefused) end)
      assert {:error, %Req.TransportError{reason: :econnrefused}} = Resend.list_received()
    end
  end

  describe "list_received_all/1" do
    test "follows the after cursor until has_more is false" do
      pages = %{
        nil => {["em_1", "em_2"], true},
        "em_2" => {["em_3"], true},
        "em_3" => {[], false}
      }

      Req.Test.stub(Resend, fn conn ->
        {ids, has_more} = Map.fetch!(pages, conn.query_params["after"])
        data = Enum.map(ids, &received_email(%{id: &1}))
        Req.Test.json(conn, %{"object" => "list", "has_more" => has_more, "data" => data})
      end)

      assert {:ok, emails} = Resend.list_received_all()
      assert Enum.map(emails, & &1["id"]) == ["em_1", "em_2", "em_3"]
    end

    test "stops when a page comes back empty despite has_more" do
      Req.Test.stub(Resend, fn conn ->
        Req.Test.json(conn, %{"object" => "list", "has_more" => true, "data" => []})
      end)

      assert {:ok, []} = Resend.list_received_all()
    end

    test "propagates an error raised part-way through the pages" do
      Req.Test.stub(Resend, fn conn ->
        case conn.query_params["after"] do
          nil ->
            Req.Test.json(conn, %{
              "object" => "list",
              "has_more" => true,
              "data" => [received_email(%{id: "em_1"})]
            })

          "em_1" ->
            conn |> Plug.Conn.put_status(500) |> Req.Test.json(%{"message" => "boom"})
        end
      end)

      assert {:error, {:unexpected_status, 500}} = Resend.list_received_all()
    end

    test "stops after max_pages" do
      Req.Test.stub(Resend, fn conn ->
        id = "em_" <> Integer.to_string(System.unique_integer([:positive]))

        Req.Test.json(conn, %{
          "object" => "list",
          "has_more" => true,
          "data" => [received_email(%{id: id})]
        })
      end)

      assert {:ok, emails} = Resend.list_received_all(2)
      assert length(emails) == 2
    end
  end
end
