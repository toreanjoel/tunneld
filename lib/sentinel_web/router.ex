defmodule SentinelWeb.Router do
  use SentinelWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {SentinelWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :browser_storybook do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {SentinelWeb.Layouts, :storybook}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

   pipeline :browser_dashboard do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {SentinelWeb.Layouts, :dashboard}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  pipeline :set_ip do
    plug SentinelWeb.Plugs.SetIp
  end

  # These are the open routes
  scope "/", SentinelWeb do
    pipe_through [:browser, :set_ip]

    live "/", Live.Login
    live "/dashboard", Live.DashboardV2
  end

  # Sentinel Dashboard UI
  scope "/", SentinelWeb do
    pipe_through [:browser_dashboard]

    live "/v2/dashboard", Live.DashboardV2
  end

  # controller to manage the file downloads
  scope "/files", SentinelWeb do
    pipe_through [:browser]

    get "/download/:name", Controllers.FileDownloadController, :download
  end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:sentinel, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser
      live_dashboard "/dashboard", metrics: SentinelWeb.Telemetry
    end
  end

  # Fallback for any unknown routes
  scope "/*path", SentinelWeb do
    pipe_through [:browser]

    live "/", Live.NotFound
  end
end
