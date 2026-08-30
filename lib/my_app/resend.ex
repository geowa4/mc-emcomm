defmodule MyApp.Resend do
  @moduledoc """
  Minimal Resend API client (Req). The API key comes from
  `config :my_app, :resend_api_key` (set in `config/runtime.exs`).

  In test, `config :my_app, MyApp.Resend, req_options: [plug: {Req.Test, MyApp.Resend}]`
  routes every request to a `Req.Test` stub. Consumers depend on the
  `MyApp.Resend.Client` behaviour instead and are tested against
  `MyApp.ResendMock` (Mox).
  """

  @behaviour MyApp.Resend.Client

  @base_url "https://api.resend.com"
  @page_size 100
  @max_pages 5

  @typedoc "A received-email object as returned by the Receiving API."
  @type email :: %{optional(String.t()) => term()}

  @doc """
  Lists received emails (`GET /emails/receiving`), one page.

  Accepts the endpoint's query params (`limit`, `after`, `before`). Returns the
  `data` list plus the `has_more` flag so callers can paginate.
  """
  @spec list_received(keyword()) ::
          {:ok, [email()], boolean()}
          | {:error,
             :missing_api_key
             | :unexpected_body
             | {:unexpected_status, pos_integer()}
             | Exception.t()}
  def list_received(params \\ []) do
    with {:ok, key} <- api_key() do
      [url: @base_url <> "/emails/receiving", auth: {:bearer, key}, params: params]
      |> Keyword.merge(req_options())
      |> Req.get()
      |> case do
        {:ok, %Req.Response{status: 200, body: %{"data" => data} = body}} ->
          {:ok, data, body["has_more"] == true}

        {:ok, %Req.Response{status: 200}} ->
          {:error, :unexpected_body}

        {:ok, %Req.Response{} = resp} ->
          {:error, {:unexpected_status, resp.status}}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  @doc """
  Lists received emails across pages by following the `after` cursor, newest
  first, up to `max_pages` pages of #{@page_size}.
  """
  @spec list_received_all(non_neg_integer()) :: {:ok, [email()]} | {:error, term()}
  @impl true
  def list_received_all(max_pages \\ @max_pages), do: fetch_pages([], nil, max_pages)

  defp fetch_pages(acc, _cursor, 0), do: {:ok, acc}

  defp fetch_pages(acc, cursor, pages_left) do
    params = [limit: @page_size] ++ if(cursor, do: [after: cursor], else: [])

    case list_received(params) do
      {:ok, data, true} when data != [] ->
        fetch_pages(acc ++ data, List.last(data)["id"], pages_left - 1)

      {:ok, data, _has_more} ->
        {:ok, acc ++ data}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp api_key do
    case Application.get_env(:my_app, :resend_api_key) do
      key when is_binary(key) and key != "" -> {:ok, key}
      _ -> {:error, :missing_api_key}
    end
  end

  defp req_options do
    :my_app |> Application.get_env(__MODULE__, []) |> Keyword.get(:req_options, [])
  end
end
