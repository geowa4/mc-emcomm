defmodule McEmcomm.MCP.ToolsTest do
  @moduledoc """
  Drives the tools through `McEmcomm.MCP.Tools.Registry.call/3` exactly as
  the transport does, with contexts built from real users, so scope, live
  role, argument validation, and output-schema conformance are all exercised.
  """
  use McEmcomm.DataCase, async: true

  alias McEmcomm.Accounts.Scope
  alias McEmcomm.McEmcommFixtures
  alias McEmcomm.MCP.Context
  alias McEmcomm.MCP.Tools.Registry
  alias McEmcomm.Members
  alias McEmcomm.Net
  alias McEmcomm.OAuth.Scopes
  alias McEmcomm.Operations

  defp context(user, scopes \\ nil) do
    scope = Scope.for_user(user)

    %Context{
      scope: scope,
      scopes: scopes || Scopes.permitted_for(scope),
      client_id: "test-client",
      token_id: System.unique_integer([:positive])
    }
  end

  defp call!(context, name, args \\ %{}) do
    {:ok, %{"isError" => false, "structuredContent" => structured}} =
      Registry.call(name, args, context)

    structured
  end

  defp error!(context, name, args \\ %{}) do
    {:ok, %{"isError" => true, "content" => [%{"text" => text}]}} =
      Registry.call(name, args, context)

    text
  end

  setup do
    member = McEmcommFixtures.member_fixture(%{call_sign: "W2NET"})
    admin = McEmcommFixtures.admin_scope_fixture().user
    %{member: member, member_ctx: context(member.user), admin: admin, admin_ctx: context(admin)}
  end

  describe "net logger" do
    test "start_net → add_checkin → list_net_checkins → end_net", %{
      member_ctx: ctx,
      member: member
    } do
      keyword = McEmcommFixtures.unique_aprs_keyword()
      net = call!(ctx, "start_net", %{"name" => "Tuesday Net", "aprs_keyword" => keyword})
      assert net["on_air"]
      assert net["aprs_keyword"] == keyword
      assert net["net_control_member_id"] == member.id

      assert [%{"id" => id}] =
               call!(ctx, "list_active_nets")["nets"] |> Enum.filter(&(&1["id"] == net["id"]))

      assert id == net["id"]

      other = McEmcommFixtures.member_fixture(%{call_sign: "W2ABC"})

      {:ok, _} =
        Members.update_profile(other, %{qth_point: McEmcommFixtures.geo_point(-77.7, 43.2)})

      checkin =
        call!(ctx, "add_checkin", %{
          "net_id" => net["id"],
          "call_sign" => "w2abc",
          "notes" => "mobile"
        })

      assert checkin["call_sign"] == "W2ABC"
      assert checkin["member_id"] == other.id
      assert checkin["member_name"] == other.name
      assert checkin["location_name"] == "QTH"
      assert checkin["location"] == %{"lat" => 43.2, "lng" => -77.7}
      assert is_nil(checkin["ended_at"])

      listing = call!(ctx, "list_net_checkins", %{"net_id" => net["id"]})
      assert listing["net"]["id"] == net["id"]
      assert Enum.map(listing["checkins"], & &1["call_sign"]) == ["W2NET", "W2ABC"]
      assert is_nil(listing["next_cursor"])

      ended = call!(ctx, "end_net", %{"net_id" => net["id"]})
      refute ended["on_air"]
      assert ended["ended_at"]

      assert Enum.all?(
               call!(ctx, "list_net_checkins", %{"net_id" => net["id"]})["checkins"],
               & &1["ended_at"]
             )

      assert error!(ctx, "add_checkin", %{"net_id" => net["id"], "call_sign" => "W2XYZ"}) =~
               "ended"

      # Ending twice is idempotent.
      assert call!(ctx, "end_net", %{"net_id" => net["id"]})["id"] == net["id"]
    end

    test "add_checkin resolves catalog and operation location names, and rejects unknown ones", %{
      member_ctx: ctx
    } do
      location = McEmcommFixtures.default_location_fixture(%{name: "NW Rally"})
      operation = McEmcommFixtures.operation_fixture(%{}, %{"name" => "Staging"})

      net =
        call!(ctx, "start_net", %{
          "aprs_keyword" => McEmcommFixtures.unique_aprs_keyword(),
          "operation_id" => operation.id
        })

      by_catalog =
        call!(ctx, "add_checkin", %{
          "net_id" => net["id"],
          "call_sign" => "W2AAA",
          "location" => "nw rally"
        })

      assert by_catalog["location_name"] == "NW Rally"

      assert by_catalog["location"]["lat"] ==
               McEmcomm.MCP.Tools.Present.point(location.point)["lat"]

      by_op =
        call!(ctx, "add_checkin", %{
          "net_id" => net["id"],
          "call_sign" => "W2BBB",
          "location" => "Staging"
        })

      assert by_op["location_name"] == "Staging"

      none =
        call!(ctx, "add_checkin", %{
          "net_id" => net["id"],
          "call_sign" => "W2CCC",
          "location" => "none"
        })

      assert is_nil(none["location_name"])

      text =
        error!(ctx, "add_checkin", %{
          "net_id" => net["id"],
          "call_sign" => "W2DDD",
          "location" => "Mars"
        })

      assert text =~ "Unknown location"
      assert text =~ "NW Rally"
      assert text =~ "Staging"
    end

    test "add_checkin is idempotent on idempotency_key", %{member_ctx: ctx} do
      net = call!(ctx, "start_net", %{"aprs_keyword" => McEmcommFixtures.unique_aprs_keyword()})
      args = %{"net_id" => net["id"], "call_sign" => "W2IDEM", "idempotency_key" => "retry-1"}

      first = call!(ctx, "add_checkin", args)
      second = call!(ctx, "add_checkin", args)
      assert second["id"] == first["id"]

      third = call!(ctx, "add_checkin", %{args | "idempotency_key" => "retry-2"})
      refute third["id"] == first["id"]

      checkins = call!(ctx, "list_net_checkins", %{"net_id" => net["id"]})["checkins"]
      assert Enum.count(checkins, &(&1["call_sign"] == "W2IDEM")) == 2
    end

    test "unknown nets are reported, not crashed", %{member_ctx: ctx} do
      assert error!(ctx, "end_net", %{"net_id" => 999_999}) =~ "not found"
      assert error!(ctx, "list_net_checkins", %{"net_id" => 999_999}) =~ "not found"
    end

    test "an admin without a member profile can read nets but not run them", %{admin_ctx: ctx} do
      assert call!(ctx, "list_active_nets")["nets"] |> is_list()
      assert error!(ctx, "start_net", %{"aprs_keyword" => "ADMINX"}) =~ "approved member profile"
    end
  end

  describe "pagination" do
    test "list tools page with opaque cursors", %{member_ctx: ctx} do
      for i <- 1..55,
          do:
            McEmcommFixtures.asset_fixture(%{name: "Asset #{String.pad_leading("#{i}", 3, "0")}"})

      first = call!(ctx, "list_assets")
      assert length(first["assets"]) == 50
      assert is_binary(first["next_cursor"])

      second = call!(ctx, "list_assets", %{"cursor" => first["next_cursor"]})
      assert length(second["assets"]) == 5
      assert is_nil(second["next_cursor"])

      names = Enum.map(first["assets"] ++ second["assets"], & &1["name"])
      assert names == Enum.sort(names)
      assert error!(ctx, "list_assets", %{"cursor" => "junk"}) =~ "cursor"
    end
  end

  describe "operations" do
    test "members read, admins write", %{member_ctx: member_ctx, admin_ctx: admin_ctx} do
      assert error!(member_ctx, "create_op", %{}) =~ "administrator"

      op =
        call!(admin_ctx, "create_op", %{
          "title" => "Field Day",
          "starts_at" => "2026-06-27T18:00:00Z",
          "ends_at" => "2026-06-28T18:00:00Z",
          "visibility" => "public",
          "locations" => [
            %{
              "name" => "Park",
              "location" => %{"lat" => 43.1, "lng" => -77.6},
              "geofence_radius_m" => 300
            },
            %{"name" => "Lot", "location" => %{"lat" => 43.2, "lng" => -77.7}}
          ]
        })

      assert op["title"] == "Field Day"
      assert op["visibility"] == "public"

      assert Enum.map(op["locations"], & &1["name"]) == ["Park", "Lot"]
      assert Enum.map(op["locations"], & &1["geofence_radius_m"]) == [300, 500]

      fetched = call!(member_ctx, "get_op", %{"operation_id" => op["id"]})
      assert fetched["id"] == op["id"]
      assert length(fetched["locations"]) == 2

      updated =
        call!(admin_ctx, "update_op", %{"operation_id" => op["id"], "title" => "Field Day 2026"})

      assert updated["title"] == "Field Day 2026"

      added =
        call!(admin_ctx, "add_op_location", %{
          "operation_id" => op["id"],
          "name" => "Overflow",
          "location" => %{"lat" => 43.3, "lng" => -77.8}
        })

      assert added["name"] == "Overflow"
      assert added["geofence_radius_m"] == 500

      removed =
        call!(admin_ctx, "remove_op_location", %{
          "operation_id" => op["id"],
          "location_id" => added["id"]
        })

      assert removed["id"] == added["id"]

      assert error!(admin_ctx, "remove_op_location", %{
               "operation_id" => op["id"],
               "location_id" => added["id"]
             }) =~ "no location"

      listed = call!(member_ctx, "list_ops", %{"visibility" => "public"})
      assert Enum.any?(listed["operations"], &(&1["id"] == op["id"]))

      deleted = call!(admin_ctx, "delete_op", %{"operation_id" => op["id"]})
      assert deleted["id"] == op["id"]
      assert error!(member_ctx, "get_op", %{"operation_id" => op["id"]}) =~ "not found"
    end

    test "create_op validates its dates and window", %{admin_ctx: ctx} do
      assert error!(ctx, "create_op", %{
               "title" => "x",
               "starts_at" => "yesterday",
               "ends_at" => "2026-06-28T18:00:00Z",
               "locations" => [%{"location" => %{"lat" => 1, "lng" => 1}}]
             }) =~ "starts_at must be an ISO 8601"

      assert error!(ctx, "create_op", %{
               "title" => "x",
               "starts_at" => "2026-06-28T18:00:00Z",
               "ends_at" => "2026-06-27T18:00:00Z",
               "locations" => [%{"location" => %{"lat" => 1, "lng" => 1}}]
             }) =~ "ends_at must be after the start time"

      assert error!(ctx, "create_op", %{
               "title" => "x",
               "starts_at" => "2026-06-27T18:00:00Z",
               "ends_at" => "2026-06-28T18:00:00Z",
               "locations" => []
             }) =~ "at least one location"
    end

    test "attendance is marked for the caller only, once", %{member_ctx: ctx, member: member} do
      operation = McEmcommFixtures.operation_fixture()
      marked = call!(ctx, "mark_op_attendance", %{"operation_id" => operation.id})
      assert marked["member_id"] == member.id
      assert marked["source"] == "manual"

      assert call!(ctx, "mark_op_attendance", %{"operation_id" => operation.id})["member_id"] ==
               member.id

      assert [%{"member_id" => id}] =
               call!(ctx, "list_op_attendance", %{"operation_id" => operation.id})["attendance"]

      assert id == member.id
      assert length(Operations.list_attendance(operation.id)) == 1
    end
  end

  describe "membership" do
    test "admins approve, transition, list, and inspect members; members get a tool error", ctx do
      pending = McEmcommFixtures.pending_member_fixture(%{call_sign: "W2PEND"})

      assert error!(ctx.member_ctx, "list_pending_members") =~ "administrator"
      assert error!(ctx.member_ctx, "get_member", %{"member_id" => pending.id}) =~ "administrator"

      assert Enum.any?(
               call!(ctx.admin_ctx, "list_pending_members")["members"],
               &(&1["id"] == pending.id)
             )

      approved = call!(ctx.admin_ctx, "approve_member", %{"member_id" => pending.id})
      assert approved["status"] == "approved"

      assert error!(ctx.admin_ctx, "approve_member", %{"member_id" => pending.id}) =~
               "not allowed"

      assert error!(ctx.admin_ctx, "transition_member", %{
               "member_id" => pending.id,
               "to_status" => "inactive"
             }) =~
               "reason"

      inactive =
        call!(ctx.admin_ctx, "transition_member", %{
          "member_id" => pending.id,
          "to_status" => "inactive",
          "reason" => "Moved out of county"
        })

      assert inactive["status"] == "inactive"

      detail = call!(ctx.admin_ctx, "get_member", %{"member_id" => pending.id})

      assert Enum.map(detail["audit"], &{&1["from_status"], &1["to_status"]}) == [
               {"approved", "inactive"},
               {"pending", "approved"}
             ]

      assert [%{"reason" => "Moved out of county"} | _] = detail["audit"]

      listed = call!(ctx.admin_ctx, "list_members", %{"status" => "inactive"})
      assert Enum.map(listed["members"], & &1["id"]) == [pending.id]
    end

    test "the admin view carries the emergency contact and home location", ctx do
      {:ok, member} =
        Members.update_profile(ctx.member, %{
          qth_address: "1 Main St",
          qth_point: McEmcommFixtures.geo_point(),
          emergency_contact_name: "Pat Example",
          emergency_contact_phone: "555-0100"
        })

      detail = call!(ctx.admin_ctx, "get_member", %{"member_id" => member.id})
      assert detail["qth_address"] == "1 Main St"
      assert detail["qth"]["lat"] == 43.1566

      assert detail["emergency_contact"] == %{
               "name" => "Pat Example",
               "phone" => "555-0100",
               "relation" => nil
             }
    end
  end

  describe "profile" do
    test "get_my_profile and update_my_profile act on the caller only", %{
      member_ctx: ctx,
      member: member
    } do
      profile = call!(ctx, "get_my_profile")
      assert profile["member_id"] == member.id
      assert profile["call_sign"] == "W2NET"
      assert profile["admin"] == false
      assert profile["capabilities"] == []

      capability = McEmcommFixtures.capability_fixture(%{name: "HF voice"})

      {:ok, _} =
        McEmcomm.Capabilities.add_member_capability(%{
          member_id: member.id,
          capability_id: capability.id
        })

      updated =
        call!(ctx, "update_my_profile", %{
          "name" => "New Name",
          "license_class" => "general",
          "qth" => %{"lat" => 43.2, "lng" => -77.7},
          "emergency_contact_name" => "Pat",
          "emergency_contact_phone" => "555-0100"
        })

      assert updated["name"] == "New Name"
      assert updated["license_class"] == "general"
      assert updated["qth"] == %{"lat" => 43.2, "lng" => -77.7}
      assert updated["emergency_contact"]["name"] == "Pat"
      assert updated["capabilities"] == [%{"id" => capability.id, "name" => "HF voice"}]

      assert error!(ctx, "update_my_profile", %{"emergency_contact_relation" => "Spouse"}) =~
               "emergency_contact_name"

      assert error!(ctx, "update_my_profile", %{"bogus" => 1}) =~ "not a recognized property"
    end

    test "an admin without a profile is told to register one", %{admin_ctx: ctx} do
      assert error!(ctx, "get_my_profile") =~ "no member profile"
    end
  end

  describe "equipment and catalogs" do
    test "members read; only admins write; sightings use the member projection", ctx do
      asset = McEmcommFixtures.asset_fixture(%{name: "Go Kit"})
      retired = McEmcommFixtures.asset_fixture(%{name: "Old Radio", active: false})

      {:ok, sighting} =
        McEmcomm.Sightings.record_visit(%{
          asset_id: asset.id,
          session_token: "tok",
          visited_at: DateTime.utc_now(),
          remote_ip: "203.0.113.1",
          user_agent: "Mozilla/5.0"
        })

      {:ok, _} =
        McEmcomm.Sightings.submit(sighting, %{"call_sign" => "w2see", "note" => "at the EOC"})

      listed = call!(ctx.member_ctx, "list_assets")
      assert Enum.map(listed["assets"], & &1["name"]) == ["Go Kit"]

      assert call!(ctx.admin_ctx, "list_assets", %{"include_inactive" => true})["assets"]
             |> length() == 2

      assert call!(ctx.member_ctx, "list_assets", %{"include_inactive" => true})["assets"]
             |> length() == 1

      detail = call!(ctx.member_ctx, "get_asset", %{"public_id" => asset.public_id})
      assert detail["id"] == asset.id
      assert detail["sighting_url"] =~ "/a/#{asset.public_id}/s"
      assert [%{"call_sign" => "W2SEE", "note" => "at the EOC"} = seen] = detail["sightings"]
      refute Map.has_key?(seen, "remote_ip")
      refute Map.has_key?(seen, "user_agent")

      assert Map.keys(seen) |> Enum.sort() ==
               ~w(call_sign claimed_responsibility id note operation_id submitted_at verified)

      assert error!(ctx.member_ctx, "create_asset", %{"name" => "x"}) =~ "administrator"
      created = call!(ctx.admin_ctx, "create_asset", %{"name" => "Trailer"})
      assert created["public_id"] =~ ~r/^[0-9A-HJKMNP-TV-Z]{6}$/

      assert call!(ctx.admin_ctx, "update_asset", %{"asset_id" => retired.id, "active" => true})[
               "active"
             ]

      assert error!(ctx.member_ctx, "get_asset", %{"public_id" => "ZZZZZZ"}) =~ "No asset"
    end

    test "catalog items, locations, and documents", ctx do
      course =
        call!(ctx.admin_ctx, "create_catalog_item", %{
          "kind" => "course",
          "name" => "AUXCOMM",
          "code" => "AUXC"
        })

      assert course["kind"] == "course"

      cert =
        call!(ctx.admin_ctx, "create_catalog_item", %{
          "kind" => "certification",
          "name" => "AUXC",
          "prerequisite_course_id" => course["id"],
          "requires_task_book" => true
        })

      assert cert["prerequisite_course_id"] == course["id"]

      assert error!(ctx.admin_ctx, "create_catalog_item", %{
               "kind" => "course",
               "name" => "AUXCOMM"
             }) =~ "taken"

      assert error!(ctx.member_ctx, "create_catalog_item", %{"kind" => "course", "name" => "x"}) =~
               "administrator"

      hidden =
        call!(ctx.admin_ctx, "update_catalog_item", %{
          "kind" => "course",
          "id" => course["id"],
          "active" => false
        })

      refute hidden["active"]
      assert call!(ctx.member_ctx, "list_catalog", %{"kind" => "course"})["items"] == []

      assert call!(ctx.admin_ctx, "list_catalog", %{
               "kind" => "course",
               "include_inactive" => true
             })["items"]
             |> length() == 1

      assert error!(ctx.admin_ctx, "update_catalog_item", %{"kind" => "course", "id" => 999_999}) =~
               "not found"

      loc =
        call!(ctx.admin_ctx, "create_location", %{
          "name" => "NE",
          "location" => %{"lat" => 43.2, "lng" => -77.5}
        })

      moved =
        call!(ctx.admin_ctx, "update_location", %{
          "location_id" => loc["id"],
          "location" => %{"lat" => 43.3, "lng" => -77.4}
        })

      assert moved["location"] == %{"lat" => 43.3, "lng" => -77.4}
      assert [%{"name" => "NE"}] = call!(ctx.member_ctx, "list_locations")["locations"]

      McEmcommFixtures.document_fixture(%{title: "Members Handbook", members_only: true})
      McEmcommFixtures.document_fixture(%{title: "Retired", active: false})

      assert [%{"title" => "Members Handbook", "members_only" => true}] =
               call!(ctx.member_ctx, "list_documents")["documents"]
    end
  end

  describe "scope enforcement" do
    test "a token lacking a scope the role could hold is a step-up, not a tool error", %{
      member: member
    } do
      narrow = context(member.user, ["emcomm:member"])

      assert Registry.call("list_ops", %{}, narrow) ==
               {:error, {:insufficient_scope, "emcomm:operations"}}

      assert {:ok, %{"isError" => false}} = Registry.call("list_active_nets", %{}, narrow)
    end

    test "every tool denies a pending member and an unknown tool is a protocol error" do
      pending = McEmcommFixtures.pending_member_fixture()
      ctx = context(pending.user, Scopes.all())

      for tool <- Registry.all() do
        {:ok, %{"isError" => true, "content" => [%{"text" => text}]}} =
          Registry.call(tool.name(), %{}, ctx)

        assert text =~ "approved member" or text =~ "administrator", tool.name()
      end

      assert Registry.call("nope", %{}, ctx) == {:error, :unknown_tool}
    end

    test "every admin tool denies an approved member even with every scope", %{member: member} do
      ctx = context(member.user, Scopes.all())

      for tool <- Registry.all(), tool.required_role() == :admin do
        {:ok, %{"isError" => true, "content" => [%{"text" => text}]}} =
          Registry.call(tool.name(), %{}, ctx)

        assert text =~ "administrator", tool.name()
      end
    end

    test "every tool's declared scope is one the server issues and names are within limits" do
      for tool <- Registry.all() do
        assert tool.required_scope() in Scopes.all()
        assert tool.required_role() in [:member, :admin]
        assert String.length(tool.name()) <= 30
      end

      assert Registry.all() |> Enum.map(& &1.name()) |> Enum.uniq() |> length() ==
               length(Registry.all())
    end
  end

  test "Net.check_in/2 honours idempotency_key without an MCP context" do
    member = McEmcommFixtures.member_fixture()
    session = McEmcommFixtures.net_session_fixture(member)
    attrs = %{"call_sign" => "W2DUP", "idempotency_key" => "k"}
    {:ok, first} = Net.check_in(session, attrs)
    {:ok, second} = Net.check_in(session, attrs)
    assert second.id == first.id
  end
end
