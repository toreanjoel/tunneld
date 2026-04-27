defmodule TunneldWeb.Router do
  use TunneldWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {TunneldWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  pipeline :set_client_id do
    plug TunneldWeb.Plugs.SetClientId
  end

  scope "/api", TunneldWeb do
    pipe_through :api
    get "/health", HealthController, :index

    scope "/v1" do
      post "/expose", ExposeController, :create
      get "/expose", ExposeController, :index
      delete "/expose/:name", ExposeController, :delete
    end
  end

  # These are the open routes
  scope "/", TunneldWeb do
    pipe_through [:browser, :set_client_id]

    live "/", Live.Login
    live "/setup", Live.Setup
    live "/dashboard", Live.Dashboard
  end

  if Application.compile_env(:tunneld, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser
      live_dashboard "/dashboard", metrics: TunneldWeb.Telemetry
    end
  end

  # Fallback for any unknown routes
  scope "/*path", TunneldWeb do
    pipe_through [:browser]

    live "/", Live.NotFound
  end
end
