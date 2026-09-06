defmodule McEmcomm.MCP.Schema do
  @moduledoc """
  A hand-rolled validator for the JSON Schema 2020-12 subset the MCP tools
  use: `type` (string, integer, number, boolean, array, object, null, or a
  list of those), `anyOf`, `enum`, `const`, `required`, `properties`,
  `additionalProperties: false`, `items`, `minimum`, `maximum`, `minLength`,
  `maxLength`, `minItems`, `maxItems`. Other keywords (`description`,
  `format`, `default`, `title`) are documentation and are ignored.

  Should full Draft 2020-12 validation ever be needed, the one approved
  dependency is `jsv` (MIT); `ex_json_schema` is not to be used (SPEC.md §28).
  """

  @type error :: String.t()

  @doc "Validates `value` against `schema`, returning every violation found."
  @spec validate(map(), term()) :: :ok | {:error, [error()]}
  def validate(schema, value) when is_map(schema) do
    case errors(schema, value, "") do
      [] -> :ok
      errors -> {:error, errors}
    end
  end

  @doc "Validates and returns the messages as one sentence, for tool errors."
  @spec explain(map(), term()) :: :ok | {:error, String.t()}
  def explain(schema, value) do
    case validate(schema, value) do
      :ok -> :ok
      {:error, errors} -> {:error, Enum.join(errors, "; ")}
    end
  end

  defp errors(schema, value, path) do
    any_of_errors(schema, value, path) ++
      type_errors(schema, value, path) ++
      enum_errors(schema, value, path) ++
      const_errors(schema, value, path) ++
      object_errors(schema, value, path) ++
      array_errors(schema, value, path) ++
      number_errors(schema, value, path) ++
      string_errors(schema, value, path)
  end

  ## anyOf

  # Valid when at least one branch accepts the value. The branches' own
  # messages are not surfaced: for the nullable pattern this validator is
  # used for, "must be a string or null" reads better than two half-messages.
  defp any_of_errors(%{"anyOf" => branches}, value, path) when is_list(branches) do
    if Enum.any?(branches, &(errors(&1, value, path) == [])) do
      []
    else
      types = Enum.map(branches, &to_string(&1["type"] || "an allowed form"))
      ["#{label(path)} must be #{Enum.join(types, " or ")}"]
    end
  end

  defp any_of_errors(_schema, _value, _path), do: []

  ## type

  defp type_errors(%{"type" => types}, value, path) when is_list(types) do
    if Enum.any?(types, &of_type?(&1, value)),
      do: [],
      else: ["#{label(path)} must be #{Enum.join(types, " or ")}"]
  end

  defp type_errors(%{"type" => type}, value, path) when is_binary(type) do
    if of_type?(type, value), do: [], else: ["#{label(path)} must be #{article(type)}"]
  end

  defp type_errors(_schema, _value, _path), do: []

  defp of_type?("string", value), do: is_binary(value)

  defp of_type?("integer", value),
    do: is_integer(value) or (is_float(value) and value == trunc(value))

  defp of_type?("number", value), do: is_number(value)
  defp of_type?("boolean", value), do: is_boolean(value)
  defp of_type?("array", value), do: is_list(value)
  defp of_type?("object", value), do: is_map(value)
  defp of_type?("null", value), do: is_nil(value)
  defp of_type?(_type, _value), do: false

  ## enum / const

  defp enum_errors(%{"enum" => allowed}, value, path) when is_list(allowed) do
    if value in allowed,
      do: [],
      else: ["#{label(path)} must be one of: #{Enum.map_join(allowed, ", ", &inspect/1)}"]
  end

  defp enum_errors(_schema, _value, _path), do: []

  defp const_errors(%{"const" => expected}, value, path) do
    if value == expected, do: [], else: ["#{label(path)} must be #{inspect(expected)}"]
  end

  defp const_errors(_schema, _value, _path), do: []

  ## object

  defp object_errors(schema, value, path) when is_map(value) do
    properties = Map.get(schema, "properties", %{})

    required =
      for key <- Map.get(schema, "required", []), not Map.has_key?(value, key) do
        "#{label(join(path, key))} is required"
      end

    additional? = Map.get(schema, "additionalProperties", true) != false

    nested =
      Enum.flat_map(value, fn {key, child} ->
        property_errors(Map.fetch(properties, key), child, join(path, key), additional?)
      end)

    required ++ nested
  end

  defp object_errors(_schema, _value, _path), do: []

  defp property_errors({:ok, child_schema}, child, path, _additional?) when is_map(child_schema),
    do: errors(child_schema, child, path)

  defp property_errors({:ok, _permissive}, _child, _path, _additional?), do: []
  defp property_errors(:error, _child, _path, true), do: []

  defp property_errors(:error, _child, path, false),
    do: ["#{label(path)} is not a recognized property"]

  ## array

  defp array_errors(schema, value, path) when is_list(value) do
    count = length(value)

    bounds =
      List.flatten([
        if(is_integer(schema["minItems"]) and count < schema["minItems"],
          do: ["#{label(path)} must have at least #{schema["minItems"]} items"],
          else: []
        ),
        if(is_integer(schema["maxItems"]) and count > schema["maxItems"],
          do: ["#{label(path)} must have at most #{schema["maxItems"]} items"],
          else: []
        )
      ])

    items =
      case schema["items"] do
        %{} = item_schema ->
          value
          |> Enum.with_index()
          |> Enum.flat_map(fn {item, index} -> errors(item_schema, item, "#{path}[#{index}]") end)

        _ ->
          []
      end

    bounds ++ items
  end

  defp array_errors(_schema, _value, _path), do: []

  ## number

  defp number_errors(schema, value, path) when is_number(value) do
    List.flatten([
      if(is_number(schema["minimum"]) and value < schema["minimum"],
        do: ["#{label(path)} must be at least #{schema["minimum"]}"],
        else: []
      ),
      if(is_number(schema["maximum"]) and value > schema["maximum"],
        do: ["#{label(path)} must be at most #{schema["maximum"]}"],
        else: []
      )
    ])
  end

  defp number_errors(_schema, _value, _path), do: []

  ## string

  defp string_errors(schema, value, path) when is_binary(value) do
    length = String.length(value)

    List.flatten([
      if(is_integer(schema["minLength"]) and length < schema["minLength"],
        do: ["#{label(path)} must be at least #{schema["minLength"]} characters"],
        else: []
      ),
      if(is_integer(schema["maxLength"]) and length > schema["maxLength"],
        do: ["#{label(path)} must be at most #{schema["maxLength"]} characters"],
        else: []
      )
    ])
  end

  defp string_errors(_schema, _value, _path), do: []

  defp join("", key), do: key
  defp join(path, key), do: "#{path}.#{key}"

  defp label(""), do: "value"
  defp label(path), do: path

  defp article(type) when type in ~w(integer object array), do: "an #{type}"
  defp article(type), do: "a #{type}"
end
