defmodule McEmcomm.MCP.SchemaTest do
  use ExUnit.Case, async: true

  alias McEmcomm.MCP.Schema

  @schema %{
    "type" => "object",
    "properties" => %{
      "name" => %{"type" => "string", "minLength" => 1, "maxLength" => 5},
      "count" => %{"type" => "integer", "minimum" => 0, "maximum" => 10},
      "ratio" => %{"type" => "number"},
      "kind" => %{"type" => "string", "enum" => ["a", "b"]},
      "flag" => %{"type" => "boolean"},
      "maybe" => %{"anyOf" => [%{"type" => "string"}, %{"type" => "null"}]},
      "either" => %{"type" => ["string", "null"]},
      "tags" => %{"type" => "array", "items" => %{"type" => "string"}, "maxItems" => 2},
      "point" => %{
        "type" => "object",
        "properties" => %{"lat" => %{"type" => "number"}},
        "required" => ["lat"],
        "additionalProperties" => false
      }
    },
    "required" => ["name"],
    "additionalProperties" => false
  }

  test "accepts a conforming value" do
    assert Schema.validate(@schema, %{
             "name" => "ok",
             "count" => 3,
             "ratio" => 1.5,
             "kind" => "a",
             "flag" => true,
             "maybe" => nil,
             "either" => nil,
             "tags" => ["x"],
             "point" => %{"lat" => 43.1}
           }) == :ok
  end

  test "reports every violation with its path" do
    {:error, errors} =
      Schema.validate(@schema, %{
        "count" => 11,
        "kind" => "c",
        "flag" => "yes",
        "maybe" => 1,
        "either" => 1,
        "tags" => ["a", "b", "c"],
        "point" => %{"lng" => 1},
        "extra" => true
      })

    assert "name is required" in errors
    assert "count must be at most 10" in errors
    assert Enum.any?(errors, &String.starts_with?(&1, "kind must be one of"))
    assert "flag must be a boolean" in errors
    assert "maybe must be string or null" in errors
    assert "either must be string or null" in errors
    assert "tags must have at most 2 items" in errors
    assert "point.lat is required" in errors
    assert "point.lng is not a recognized property" in errors
    assert "extra is not a recognized property" in errors
  end

  test "checks item types, string lengths, minimums, and integer-ness" do
    {:error, errors} =
      Schema.validate(@schema, %{"name" => "toolong", "count" => -1, "tags" => [1]})

    assert "name must be at most 5 characters" in errors
    assert "count must be at least 0" in errors
    assert "tags[0] must be a string" in errors

    assert Schema.validate(@schema, %{"name" => "x", "count" => 2.0}) == :ok

    {:error, ["count must be an integer"]} =
      Schema.validate(@schema, %{"name" => "x", "count" => 2.5})
  end

  test "explain/2 joins the messages into one sentence" do
    assert {:error, message} = Schema.explain(@schema, %{})
    assert message == "name is required"
  end

  test "a non-object against an object schema is a type error" do
    assert {:error, ["value must be an object"]} = Schema.validate(@schema, [])
  end
end
