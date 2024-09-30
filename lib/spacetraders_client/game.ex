defmodule SpacetradersClient.Game do
  alias SpacetradersClient.Agents
  alias SpacetradersClient.Fleet
  alias SpacetradersClient.Systems

  @enforce_keys [:client]
  defstruct [
    :client,
    agent: %{},
    fleet: %{},
    systems: %{},
    markets: %{},
    shipyards: %{}
  ]

  def new(client) do
    %__MODULE__{client: client}
  end

  def load_agent!(game) do
    {:ok, %{status: 200, body: body}} = Agents.my_agent(game.client)

    %{game | agent: body["data"]}
  end

  def load_fleet!(game) do
    {:ok, %{status: 200, body: body}} = Fleet.list_ships(game.client)

    fleet =
      Map.new(body["data"], fn ship ->
        {ship["symbol"], ship}
      end)

    %{game | fleet: fleet}
  end

  def load_waypoint!(game, system_symbol, waypoint_symbol) do
    {:ok, %{status: 200, body: body}} = Systems.get_waypoint(game.client, system_symbol, waypoint_symbol)

    game
    |> Map.update!(:systems, fn systems ->
      systems
      |> Map.put_new(system_symbol, %{})
      |> Map.update!(system_symbol, &Map.put(&1, waypoint_symbol, body["data"]))
    end)
  end

  def load_market!(game, system_symbol, waypoint_symbol) do
    {:ok, %{status: 200, body: body}} = Systems.get_market(game.client, system_symbol, waypoint_symbol)

    game
    |> Map.update!(:markets, fn markets ->
      markets
      |> Map.put_new(system_symbol, %{})
      |> Map.update!(system_symbol, &Map.put(&1, waypoint_symbol, body["data"]))
    end)
  end

  def load_fleet_waypoints!(game) do
    game.fleet
    |> Enum.map(fn {_ship_symbol, ship} ->
      {ship["nav"]["systemSymbol"], ship["nav"]["waypointSymbol"]}
    end)
    |> Enum.uniq()
    |> Enum.reduce(game, fn {system_symbol, waypoint_symbol}, game ->
      if waypoint(game, system_symbol, waypoint_symbol) do
        game
      else
        load_waypoint!(game, system_symbol, waypoint_symbol)
      end
    end)
  end

  def load_markets!(game) do
    game.systems
    |> Enum.flat_map(fn {_system_symbol, waypoints} ->
      Enum.map(waypoints, fn {_wp_symbol, wp} ->
        wp
      end)
    end)
    |> Enum.reduce(game, fn waypoint, game ->
      traits = Enum.map(waypoint["traits"], fn t -> t["symbol"] end)

      if "MARKETPLACE" in traits do
        load_market!(game, waypoint["systemSymbol"], waypoint["symbol"])
      else
        game
      end
    end)
  end

  def ship(game, ship_symbol) do
    Map.get(game.fleet, ship_symbol)
  end

  def update_ship!(game, ship_symbol, update_fun) do
    Map.update!(game, :fleet, fn fleet ->
      Map.update!(fleet, ship_symbol, update_fun)
    end)
  end

  def waypoint(game, system_symbol, waypoint_symbol) do
    game.systems
    |> Map.get(system_symbol, %{})
    |> Map.get(waypoint_symbol)
  end

  def market(game, system_symbol, waypoint_symbol) do
    game.markets
    |> Map.get(system_symbol, %{})
    |> Map.get(waypoint_symbol)
  end
end
