defmodule McEmcommWeb.Router do
  use McEmcommWeb, :router

  import McEmcommWeb.MemberAuth, only: [require_admin_user: 2]
  import McEmcommWeb.UserAuth

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {McEmcommWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug McEmcommWeb.Plugs.ContentSecurityPolicy
    plug :put_no_store_cache_control
    plug :fetch_current_scope_for_user
  end

  # Every HTML response carries a per-request CSP nonce, a CSRF token, and the
  # session cookie, so no shared cache (CDN or otherwise) may ever store one.
  # Serving a cached page would reuse nonces across users and leak tokens; it
  # would also drop the sighting recorded on /a/:public_id/s.
  defp put_no_store_cache_control(conn, _opts) do
    put_resp_header(conn, "cache-control", "no-store")
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  # Inbound webhooks are authenticated by signature, not by session.
  pipeline :resend_webhook do
    plug :accepts, ["json"]
    plug McEmcommWeb.Plugs.VerifyResendSignature
  end

  # Update point 0 (spec §9): records the sighting row before the LiveView
  # plug, from the disconnected conn, so the visit is captured even if the
  # socket never connects.
  pipeline :record_sighting do
    plug McEmcommWeb.Plugs.RecordSighting
  end

  scope "/", McEmcommWeb do
    pipe_through :browser

    get "/", PageController, :home
  end

  ## Public (§8 :public live_session)

  scope "/", McEmcommWeb do
    pipe_through :browser

    live_session :public,
      on_mount: [{McEmcommWeb.UserAuth, :mount_current_scope}, McEmcommWeb.ActiveNet] do
      live "/about", PublicLive.About, :show
      live "/training", PublicLive.Training, :show
      live "/resources", PublicLive.Resources, :show
      live "/calendar", PublicLive.Calendar, :show
      live "/donations", PublicLive.Donations, :show
      live "/operations", OperationLive.PublicIndex, :index
      live "/operations/:id", OperationLive.PublicShow, :show
    end
  end

  scope "/", McEmcommWeb do
    pipe_through [:browser, :record_sighting]

    live_session :sighting,
      on_mount: [{McEmcommWeb.UserAuth, :mount_current_scope}, McEmcommWeb.ActiveNet] do
      live "/a/:public_id/s", SightingLive.Show, :show
    end
  end

  ## Member portal (§8 :member live_session, approved members + admins)

  scope "/app", McEmcommWeb do
    pipe_through :browser

    live_session :member,
      on_mount: [{McEmcommWeb.MemberAuth, :require_member}, McEmcommWeb.ActiveNet] do
      live "/", AppLive.Dashboard, :show
      live "/profile", AppLive.Profile, :show
      live "/operations", OperationLive.Index, :index
      live "/operations/:id", OperationLive.Show, :show
      live "/inventory", InventoryLive.Index, :index
      live "/inventory/:public_id", InventoryLive.Show, :show
      live "/net", NetLive.Console, :index
      live "/net/:id", NetLive.Show, :show
    end
  end

  ## Admin console (§8 :admin live_session)

  scope "/admin", McEmcommWeb do
    pipe_through :browser

    live_session :admin,
      on_mount: [{McEmcommWeb.MemberAuth, :require_admin}, McEmcommWeb.ActiveNet] do
      live "/", AdminLive.Dashboard, :show
      live "/members", AdminLive.MemberIndex, :index
      live "/positions", AdminLive.PositionIndex, :index
      live "/operations", AdminLive.OperationIndex, :index
      live "/operations/new", AdminLive.OperationIndex, :new
      live "/operations/:id/edit", AdminLive.OperationIndex, :edit
      live "/inventory", AdminLive.InventoryIndex, :index
      live "/capabilities", AdminLive.CapabilityIndex, :index
      live "/locations", AdminLive.DefaultLocationIndex, :index
      live "/courses", AdminLive.CourseIndex, :index
      live "/certifications", AdminLive.CertificationIndex, :index
      live "/documents", AdminLive.DocumentIndex, :index
    end
  end

  ## Health checks (no session, no CSRF; liveness has no dependencies)

  scope "/healthz", McEmcommWeb do
    get "/live", HealthController, :live
    get "/ready", HealthController, :ready
    get "/version", HealthController, :version
  end

  ## Inbound webhooks

  scope "/webhooks", McEmcommWeb do
    pipe_through :resend_webhook

    post "/resend", WebhookController, :resend
  end

  # Other scopes may use custom stacks.
  # scope "/api", McEmcommWeb do
  #   pipe_through :api
  # end

  ## LiveDashboard, behind admin authentication in every environment.
  #
  # It exposes process state, ETS contents, and the application environment
  # (Resend API key, webhook secret, database URL in production), so being
  # logged in is not enough: registration is open to the public. Reaching a
  # LiveView in another `live_session` always costs a full HTTP request, so
  # this pipeline is the only way in.

  scope "/dev" do
    pipe_through [:browser, :require_authenticated_user, :require_admin_user]

    import Phoenix.LiveDashboard.Router

    # LiveDashboard renders an inline script and stylesheet of its own; this
    # points it at the nonce McEmcommWeb.Plugs.ContentSecurityPolicy assigned.
    live_dashboard "/dashboard",
      metrics: McEmcommWeb.Telemetry,
      ecto_repos: [McEmcomm.Repo],
      csp_nonce_assign_key: %{img: :csp_nonce, style: :csp_nonce, script: :csp_nonce}
  end

  # Enable the Swoosh mailbox preview in development
  if Application.compile_env(:mc_emcomm, :dev_routes) do
    # The preview is third-party HTML with inline scripts of its own, which our
    # nonce cannot reach, so it gets the browser stack without the CSP. This
    # whole block is compiled in dev only.
    pipeline :dev_browser do
      plug :accepts, ["html"]
      plug :fetch_session
      plug :protect_from_forgery
      plug :put_secure_browser_headers
    end

    scope "/dev" do
      pipe_through :dev_browser

      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end

  ## Authentication routes

  scope "/", McEmcommWeb do
    pipe_through [:browser, :require_authenticated_user]

    live_session :require_authenticated_user,
      on_mount: [{McEmcommWeb.UserAuth, :require_authenticated}, McEmcommWeb.ActiveNet] do
      live "/users/settings", UserLive.Settings, :edit
      live "/users/settings/confirm-email/:token", UserLive.Settings, :confirm_email
      live "/users/settings/two-factor", UserLive.TwoFactor, :edit
    end

    post "/users/update-password", UserSessionController, :update_password
  end

  scope "/", McEmcommWeb do
    pipe_through [:browser]

    live_session :current_user,
      on_mount: [{McEmcommWeb.UserAuth, :mount_current_scope}, McEmcommWeb.ActiveNet] do
      live "/users/register", UserLive.Registration, :new
      live "/users/log-in", UserLive.Login, :new
      live "/users/log-in/:token", UserLive.Confirmation, :new
      live "/users/two-factor", UserLive.TwoFactorChallenge, :new
    end

    post "/users/log-in", UserSessionController, :create
    post "/users/two-factor", UserSessionController, :verify_two_factor
    delete "/users/log-out", UserSessionController, :delete
  end
end
