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

  pipeline :agent_auth do
    plug TunneldWeb.Plugs.AgentAuth
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

      get "/device/machines", DeviceController, :machines
      get "/device/machines/:id", DeviceController, :machine
      get "/device/resources", DeviceController, :resources
      get "/device/health", DeviceController, :health

      # Token issuance: admin session ONLY (tokens:issue is a forbidden scope
      # for bearer tokens). Never under agent_auth.
      scope "/agent" do
        pipe_through [:fetch_session]
        post "/tokens", AgentTokenController, :create
        get "/tokens", AgentTokenController, :index
        delete "/tokens/:id", AgentTokenController, :delete
      end

      # Agent API: scoped bearer-token auth. The product contract.
      scope "/agent" do
        pipe_through :agent_auth

        get "/machines", MachineController, :index, private: %{agent_scope: "machines:read"}
        get "/machines/:id", MachineController, :show, private: %{agent_scope: "machines:read"}
        get "/machines/:id/listeners", MachineController, :listeners, private: %{agent_scope: "machines:read"}
        post "/machines/:id/probe", MachineController, :probe_job, private: %{agent_scope: "machines:write"}
        post "/machines/:id/exec", MachineController, :exec, private: %{agent_scope: "exec"}
        delete "/machines/:id", MachineController, :delete, private: %{agent_scope: "machines:write"}

        get "/resources", AgentResourceController, :index, private: %{agent_scope: "resources:read"}
        post "/resources", AgentResourceController, :create, private: %{agent_scope: "resources:write"}
        delete "/resources/:id", AgentResourceController, :delete, private: %{agent_scope: "resources:write"}

        get "/jobs/:id", AgentResourceController, :job, private: %{agent_scope: "any"}
      end

      pipe_through [:fetch_session]
      get "/machines", MachineController, :index
      post "/machines", MachineController, :create
      get "/machines/:id", MachineController, :show
      post "/machines/:id/probe", MachineController, :probe
      get "/machines/:id/listeners", MachineController, :listeners
      delete "/machines/:id", MachineController, :delete
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
