defmodule McEmcommWeb.WebhookController do
  @moduledoc """
  Receives Resend webhooks. The signature has already been verified by
  `McEmcommWeb.Plugs.VerifyResendSignature`. Events are deduplicated on their
  `svix-id`, acknowledged with 200 immediately, and processed asynchronously
  by `McEmcomm.Inbound`.
  """
  use McEmcommWeb, :controller

  alias McEmcomm.Inbound

  def resend(conn, params) do
    [svix_id] = get_req_header(conn, "svix-id")

    case Inbound.record_event(svix_id, params["type"]) do
      {:ok, _event} ->
        {:ok, _pid} =
          Task.Supervisor.start_child(McEmcomm.TaskSupervisor, fn ->
            Inbound.handle_event(params)
          end)

        send_resp(conn, 200, "")

      {:error, :duplicate} ->
        send_resp(conn, 200, "")
    end
  end
end
