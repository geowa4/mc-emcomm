defmodule McEmcomm.Storage.S3 do
  @moduledoc """
  Real Tigris bucket access (§11) via `ReqS3`. `LiveView.allow_upload` uses
  `external:` with a presigned POST form from `ReqS3.presign_form/1`;
  viewing uses short-lived URLs from `ReqS3.presign_url/1`. Standard
  `AWS_*`/`AWS_ENDPOINT_URL_S3` env vars drive `ReqS3`.

  Callers should go through `McEmcomm.Storage`, not this module directly —
  that's what lets tests swap in `McEmcomm.StorageMock` (§18).
  """

  @behaviour McEmcomm.Storage.Client

  @download_expires_seconds 300

  @impl true
  def presign_upload(key, content_type) do
    form =
      ReqS3.presign_form(
        bucket: bucket(),
        key: key,
        content_type: content_type,
        expires_in: :timer.hours(1)
      )

    # `form.fields` is a list of 2-tuples; JSON (sent to the client as upload
    # entry metadata) can't encode tuples, so normalize to a map here once.
    %{url: form.url, fields: Map.new(form.fields)}
  end

  @impl true
  def presign_download_url(key) do
    ReqS3.presign_url(bucket: bucket(), key: key, expires: @download_expires_seconds)
  end

  @impl true
  def delete_object(key) do
    url = ReqS3.presign_url(bucket: bucket(), key: key, method: :delete, expires: 60)
    Req.delete!(url)
    :ok
  end

  defp bucket, do: Application.fetch_env!(:mc_emcomm, :s3_bucket)
end
