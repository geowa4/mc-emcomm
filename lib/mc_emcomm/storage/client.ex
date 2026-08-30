defmodule McEmcomm.Storage.Client do
  @moduledoc """
  Behaviour wrapping the two `ReqS3` presign calls the app needs (§11).
  Tests stub this behaviour (`McEmcomm.StorageMock`, see
  `test/support/mocks.ex` and `:storage_client` in `config/test.exs`) instead
  of hitting Tigris.
  """

  @callback presign_upload(key :: String.t(), content_type :: String.t() | nil) :: map()
  @callback presign_download_url(key :: String.t()) :: String.t()
  @callback delete_object(key :: String.t()) :: :ok
end
