defmodule McEmcommWeb.ParamHelpers do
  @moduledoc """
  Coercion for the record ids that arrive in `phx-value-*` event payloads.

  A LiveView event is shaped by the client, so an id that isn't an integer is
  ordinary input rather than an impossible state: `String.to_integer/1` raises
  on it and takes the LiveView process down with it. `id/1` returns nil
  instead.

  `known_id/2` narrows that to an id the socket actually rendered, which is
  what keeps a per-record upload name (`:"course_evidence_\#{id}"`) from
  turning an event payload into unbounded atom creation.
  """

  @doc "The param as an integer id, or nil when it isn't one."
  @spec id(term()) :: integer() | nil
  def id(param) when is_integer(param), do: param

  def id(param) when is_binary(param) do
    case Integer.parse(param) do
      {id, ""} -> id
      _not_an_id -> nil
    end
  end

  def id(_param), do: nil

  @doc """
  The param as an id, but only when `records` holds one carrying it, so a
  handler can decline an id the page never offered.
  """
  @spec known_id(Enumerable.t(), term()) :: integer() | nil
  def known_id(records, param) do
    id = id(param)

    if Enum.any?(records, &(&1.id == id)), do: id
  end
end
