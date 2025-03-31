defmodule SpacetradersClientWeb.Router do
  use SpacetradersClientWeb, :router

  import Oban.Web.Router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {SpacetradersClientWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", SpacetradersClientWeb do
    pipe_through :browser

    get "/", PageController, :home

    oban_dashboard("/oban")

    get "/login", SessionController, :index
    post "/login", SessionController, :log_in

    live_session :default do
      live "/game", GameLive, :agent
      live "/game/loading", LoadingLive, :index
      live "/game/contracts", ContractsLive, :index
      live "/game/agent", AgentLive, :index
      live "/game/credits", CreditsLive, :index
      live "/game/fleet", FleetLive, :index
      live "/game/fleet/:ship_symbol", GameLive, :ship
      live "/game/automation", AutomationLive, :index
      live "/game/contracts/:contract_id", GameLive, :contract
      live "/game/galaxy", GalaxyLive, :index
      live "/game/systems/:system_symbol", GameLive, :system
      live "/game/systems/:system_symbol/map", SystemLive, :map
      live "/game/systems/:system_symbol/waypoints/:waypoint_symbol", GameLive, :waypoint
    end
  end

  # Other scopes may use custom stacks.
  # scope "/api", SpacetradersClientWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:spacetraders_client, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: SpacetradersClientWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
