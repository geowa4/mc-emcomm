defmodule MyAppWeb.WebhookController do
  @moduledoc """
  Receives Resend webhooks. The signature has already been verified by
  `MyAppWeb.Plugs.VerifyResendSignature`. Events are deduplicated on their
  `svix-id`, acknowledged with 200 immediately, and processed asynchronously
  by `MyApp.Inbound`.
  """
  use MyAppWeb, :controller

  alias MyApp.Inbound

  def resend(conn, params) do
    [svix_id] = get_req_header(conn, "svix-id")

    case Inbound.record_event(svix_id, params["type"]) do
      {:ok, _event} ->
        {:ok, _pid} =
          Task.Supervisor.start_child(MyApp.TaskSupervisor, fn -> Inbound.handle_event(params) end)

        send_resp(conn, 200, "")

      {:error, :duplicate} ->
        send_resp(conn, 200, "")
    end
  end
end
