defmodule MyAppWeb.Router do
  use MyAppWeb, :router

  import MyAppWeb.UserAuth

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {MyAppWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_scope_for_user
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  # Inbound webhooks are authenticated by signature, not by session.
  pipeline :resend_webhook do
    plug :accepts, ["json"]
    plug MyAppWeb.Plugs.VerifyResendSignature
  end

  scope "/", MyAppWeb do
    pipe_through :browser

    get "/", PageController, :home
  end

  ## Health checks (no session, no CSRF; liveness has no dependencies)

  scope "/healthz", MyAppWeb do
    get "/live", HealthController, :live
    get "/ready", HealthController, :ready
    get "/version", HealthController, :version
  end

  ## Inbound webhooks

  scope "/webhooks", MyAppWeb do
    pipe_through :resend_webhook

    post "/resend", WebhookController, :resend
  end

  # Other scopes may use custom stacks.
  # scope "/api", MyAppWeb do
  #   pipe_through :api
  # end

  ## LiveDashboard, behind authentication in every environment.
  #
  # Any registered user can reach it. Before exposing a production deployment
  # to untrusted sign-ups, add an admin check to this pipeline.

  scope "/dev" do
    pipe_through [:browser, :require_authenticated_user]

    import Phoenix.LiveDashboard.Router

    live_dashboard "/dashboard", metrics: MyAppWeb.Telemetry, ecto_repos: [MyApp.Repo]
  end

  # Enable the Swoosh mailbox preview in development
  if Application.compile_env(:my_app, :dev_routes) do
    scope "/dev" do
      pipe_through :browser

      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end

  ## Authentication routes

  scope "/", MyAppWeb do
    pipe_through [:browser, :require_authenticated_user]

    live_session :require_authenticated_user,
      on_mount: [{MyAppWeb.UserAuth, :require_authenticated}] do
      live "/users/settings", UserLive.Settings, :edit
      live "/users/settings/confirm-email/:token", UserLive.Settings, :confirm_email
      live "/inbox", InboxLive, :index
    end

    post "/users/update-password", UserSessionController, :update_password
  end

  scope "/", MyAppWeb do
    pipe_through [:browser]

    live_session :current_user,
      on_mount: [{MyAppWeb.UserAuth, :mount_current_scope}] do
      live "/users/register", UserLive.Registration, :new
      live "/users/log-in", UserLive.Login, :new
      live "/users/log-in/:token", UserLive.Confirmation, :new
    end

    post "/users/log-in", UserSessionController, :create
    delete "/users/log-out", UserSessionController, :delete
  end
end
