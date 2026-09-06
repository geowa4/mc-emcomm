defmodule McEmcomm.Storage.Client do
  @moduledoc """
  Behaviour wrapping the `ReqS3` calls the app needs (§11): the two presigns,
  delete, and a server-side copy.
  Tests stub this behaviour (`McEmcomm.StorageMock`, see
  `test/support/mocks.ex` and `:storage_client` in `config/test.exs`) instead
  of hitting Tigris.
  """

  @callback presign_upload(key :: String.t(), content_type :: String.t() | nil) :: map()
  @callback presign_download_url(key :: String.t()) :: String.t()
  @callback delete_object(key :: String.t()) :: :ok
  @callback copy_object(source_key :: String.t(), destination_key :: String.t()) :: :ok
end
