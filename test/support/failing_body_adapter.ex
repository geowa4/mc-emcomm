defmodule MyAppWeb.FailingBodyAdapter do
  @moduledoc """
  Stand-in `conn.adapter` whose body read always fails, for exercising the
  `{:error, reason}` branch of body readers. Only `read_req_body/2` is
  implemented; swap it into a `Plug.Test` conn right before reading the body.
  """

  def read_req_body(_state, _opts), do: {:error, :timeout}
end
