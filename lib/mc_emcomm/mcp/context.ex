defmodule McEmcomm.MCP.Context do
  @moduledoc """
  Everything a tool may know about the caller of one `tools/call`: the
  authenticated user's `McEmcomm.Accounts.Scope` (user, member profile,
  position-derived admin), the scopes the bearer token carries, the OAuth
  client, and the client's self-reported name (display and logging only,
  never a security input). Built fresh for every request from the bearer
  token; nothing here survives the request.
  """

  alias McEmcomm.Accounts.Scope

  @type t :: %__MODULE__{
          scope: Scope.t(),
          scopes: [String.t()],
          client_id: String.t(),
          token_id: integer(),
          client_info: %{name: String.t() | nil, version: String.t() | nil}
        }

  @enforce_keys [:scope, :scopes, :client_id, :token_id]
  defstruct scope: nil,
            scopes: [],
            client_id: nil,
            token_id: nil,
            client_info: %{name: nil, version: nil}
end
