defmodule SpacetradersClient.Client do
  @moduledoc """
  HTTP client for the SpaceTraders API.
  """

  def new(token) do
    Tesla.client(
      [
        {Tesla.Middleware.BaseUrl, "https://api.spacetraders.io"},
        {Tesla.Middleware.Headers, [{"user-agent", "SpacetradersBot +https://github.com/Cantido/spacetraders_client"}]},
        {Tesla.Middleware.BearerAuth, token: token},
        Tesla.Middleware.JSON,
        SpacetradersClient.RateLimit,

      {
        Tesla.Middleware.Retry,
        delay: 5_000,
        max_delay: 30_000,
        should_retry: fn
          {:ok, %{status: status}} when status == 429 -> true
          {:ok, _} -> false
          {:error, _} -> true
        end
      },
      # Tesla.Middleware.Logger,
      ],
      {Tesla.Adapter.Finch, name: SpacetradersClient.Finch}
    )
  end

  def agent(client) do
    Tesla.get(client, "/v2/my/agent")
  end

  def systems(client) do
    Tesla.get(client, "/v2/systems")
  end

  def waypoints(client, system_symbol) do
    Tesla.get(client, "/v2/systems/#{system_symbol}/waypoints")
  end

  def market(client, system_symbol, waypoint_symbol) do
    Tesla.get(client, "/v2/systems/#{system_symbol}/waypoints/#{waypoint_symbol}/market")
  end

  def factions(client) do
    Tesla.get(client, "/v2/factions")
  end

  def my_contracts(client) do
    Tesla.get(client, "/v2/my/contracts")
  end

  def enter_orbit(client, ship_symbol) do
    Tesla.post(client, "/v2/my/ships/#{ship_symbol}/orbit", "")
  end

  def enter_dock(client, ship_symbol) do
    Tesla.post(client, "/v2/my/ships/#{ship_symbol}/dock", "")
  end

  def set_flight_mode(client, ship_symbol, flight_mode) when flight_mode in [:cruise, :burn, :drift, :stealth] do
    mode_str =
      Atom.to_string(flight_mode)
      |> String.upcase()

    Tesla.post(client, "/v2/my/ships/#{ship_symbol}/nav", %{"flightMode" => mode_str})
  end

  def navigate_to_waypoint(client, ship_symbol, waypoint_symbol) do
    Tesla.post(client, "/v2/my/ships/#{ship_symbol}/navigate", %{"waypointSymbol" => waypoint_symbol})
  end

  def warp_to_system(client, ship_symbol, system_symbol) do
    Tesla.post(client, "/v2/my/ships/#{ship_symbol}/warp", %{"systemSymbol" => system_symbol})
  end

  def jump_to_system(client, ship_symbol, system_symbol) do
    Tesla.post(client, "/v2/my/ships/#{ship_symbol}/jump", %{"systemSymbol" => system_symbol})
  end

  def extract_resources(client, ship_symbol, survey_result \\ nil) when is_binary(ship_symbol) do
    if survey_result do
      Tesla.post(client, "/v2/my/ships/#{ship_symbol}/extract", %{"survey" => survey_result})
    else
      Tesla.post(client, "/v2/my/ships/#{ship_symbol}/extract", "")
    end
  end

  def survey_resources(client, ship_symbol) do
    Tesla.post(client, "/v2/my/ships/#{ship_symbol}/survey", "")
  end

  def estimate_ship_repair_cost(client, ship_symbol) do
    Tesla.get(client, "/v2/my/ships/#{ship_symbol}/repair")
  end

  def repair_ship(client, ship_symbol) do
    Tesla.post(client, "/v2/my/ships/#{ship_symbol}/repair", "")
  end

  def estimate_ship_scrap_earnings(client, ship_symbol) do
    Tesla.get(client, "/v2/my/ships/#{ship_symbol}/scrap")
  end

  def scrap_ship(client, ship_symbol) do
    Tesla.post(client, "/v2/my/ships/#{ship_symbol}/scrap", "")
  end
end
