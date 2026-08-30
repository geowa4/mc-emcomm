defmodule McEmcomm.Repo do
  use Ecto.Repo,
    otp_app: :mc_emcomm,
    adapter: Ecto.Adapters.Postgres
end
