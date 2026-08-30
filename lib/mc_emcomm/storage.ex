defmodule McEmcomm.Storage do
  @moduledoc """
  Public entry point for private Tigris bucket access (§11). Dispatches to
  `:storage_client` (`McEmcomm.Storage.S3` in dev/prod, `McEmcomm.StorageMock`
  in test — see `config/test.exs` and §18 "Tests MUST stub the presign
  functions") so every call site here works unchanged under either.
  """

  @doc "Generates a collision-resistant object key under `prefix`, keeping the original extension."
  @spec build_key(String.t(), String.t()) :: String.t()
  def build_key(prefix, filename) do
    ext = filename |> Path.extname() |> String.downcase()
    "#{prefix}/#{Ecto.UUID.generate()}#{ext}"
  end

  @doc "Presigned POST form for an `allow_upload(external: ...)` upload target."
  def presign_upload(key, content_type), do: client().presign_upload(key, content_type)

  @doc "Short-lived signed GET URL for viewing/downloading an object."
  def presign_download_url(key), do: client().presign_download_url(key)

  @doc "Permanently deletes an object (used when purging a member's uploads on deletion, §20)."
  def delete_object(key), do: client().delete_object(key)

  defp client, do: Application.get_env(:mc_emcomm, :storage_client, McEmcomm.Storage.S3)
end
