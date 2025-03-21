defmodule SpacetradersClientWeb.Router do
  use SpacetradersClientWeb, :router

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

    get "/login", SessionController, :index
    post "/login", SessionController, :log_in
    live "/game", GameLive, :agent
    live "/game/agent", GameLive, :agent
    live "/game/fleet", GameLive, :fleet
    live "/game/contracts/:contract_id", GameLive, :contract
    live "/game/systems/:system_symbol", GameLive, :system
    live "/game/systems/:system_symbol/map", GameLive, :map
    live "/game/systems/:system_symbol/waypoints/:waypoint_symbol", GameLive, :waypoint
    live "/game/systems/:system_symbol/waypoints/:waypoint_symbol/ships/:ship_symbol", GameLive, :ship
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
