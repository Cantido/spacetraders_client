defmodule SpacetradersClient.Game do
  alias SpacetradersClient.Ship
  alias SpacetradersClient.ShipTask
  alias SpacetradersClient.Agents
  alias SpacetradersClient.Fleet
  alias SpacetradersClient.Systems

  require Logger

  @enforce_keys [:client]
  defstruct [
    :client,
    agent: %{},
    fleet: %{},
    systems: %{},
    markets: %{},
    shipyards: %{},
    surveys: %{}
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

  def load_ship!(game, ship_symbol) do
    {:ok, %{status: 200, body: body}} = Fleet.get_ship(game.client, ship_symbol)

    game
    |> Map.update!(:fleet, fn fleet ->
      Map.put(fleet, ship_symbol, body["data"])
    end)
  end

  def load_ship_cargo!(game, ship_symbol) do
    {:ok, %{status: 200, body: body}} = Fleet.get_ship_cargo(game.client, ship_symbol)

    update_ship!(game, ship_symbol, fn ship ->
      Map.put(ship, "cargo", body["data"])
    end)
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

  def add_survey(game, survey) do
    Map.update!(game, :surveys, fn surveys ->
      waypoint_symbol = Map.fetch!(survey, "symbol")

      surveys
      |> Map.put_new(waypoint_symbol, [])
      |> Map.update!(waypoint_symbol, fn survey_list ->
        [survey | survey_list]
      end)
      |> Map.new(fn {wp, surveys} ->
        surveys =
          Enum.filter(surveys, fn survey ->
            {:ok, expiration, _} = DateTime.from_iso8601(survey["expiration"])

            DateTime.before?(DateTime.utc_now(), expiration)
          end)

        {wp, surveys}
      end)
    end)
  end

  def delete_survey(game, waypoint_symbol, survey_sig) do
    Map.update!(game, :surveys, fn surveys ->
      surveys
      |> Map.put_new(waypoint_symbol, [])
      |> Map.update!(waypoint_symbol, fn survey_list ->
        Enum.reject(survey_list, fn survey ->
          survey["signature"] == survey_sig
        end)
      end)
    end)
  end

  def ship(game, ship_symbol) do
    Map.get(game.fleet, ship_symbol)
  end

  def update_ship!(%__MODULE__{} = game, ship_symbol, update_fun) do
    Map.update!(game, :fleet, fn fleet ->
      Map.update!(fleet, ship_symbol, update_fun)
    end)
  end

  def system_symbol(waypoint_symbol) when is_binary(waypoint_symbol) do
    [sector, system, _waypoint] = String.split(waypoint_symbol, "-", parts: 3)

    sector <> "-" <> system
  end

  def waypoint(game, waypoint_symbol) when is_binary(waypoint_symbol) do
    waypoint(game, system_symbol(waypoint_symbol), waypoint_symbol)
  end

  def waypoint(game, system_symbol, waypoint_symbol) do
    game.systems
    |> Map.get(system_symbol, %{})
    |> Map.get(waypoint_symbol)
  end

  def waypoints(game, system_symbol) do
    game.systems
    |> Map.get(system_symbol, %{})
    |> Enum.map(&elem(&1, 1))
  end

  def market(game, market_symbol) do
    market(game, system_symbol(market_symbol), market_symbol)
  end

  def market(game, system_symbol, waypoint_symbol) do
    game.markets
    |> Map.get(system_symbol, %{})
    |> Map.get(waypoint_symbol)
  end

  def sell_price(game, waypoint_symbol, trade_symbol) do
    sys = system_symbol(waypoint_symbol)

    market = market(game, sys, waypoint_symbol)

    Enum.find(market["tradeGoods"], %{}, fn t ->
      t["symbol"] == trade_symbol
    end)
    |> Map.get("sellPrice", 0)
  end

  def purchase_price(game, waypoint_symbol, trade_symbol) do
    sys = system_symbol(waypoint_symbol)

    market = market(game, sys, waypoint_symbol)

    Enum.find(market["tradeGoods"], %{}, fn t ->
      t["symbol"] == trade_symbol
    end)
    |> Map.get("purchasePrice", 0)
  end

  def profit(game, start_waypoint, end_waypoint, trade_symbol) do
    expense = purchase_price(game, start_waypoint, trade_symbol)
    income = sell_price(game, end_waypoint, trade_symbol)

    income - expense
  end

  def selling_markets(game, system_symbol, trade_symbol) do
    game.markets
    |> Map.get(system_symbol, %{})
    |> Enum.map(fn {_symbol, market} ->
      trade_good = Enum.find(Map.get(market, "tradeGoods", []), fn t -> t["symbol"] == trade_symbol end)

      if trade_good do
        {market, trade_good["sellPrice"]}
      else
        {market, nil}
      end
    end)
    |> Enum.reject(fn {_, price} -> is_nil(price) end)
    |> Enum.reject(fn {_, price} -> price == 0 end)
  end

  def best_selling_market_price(game, system_symbol, trade_symbol) do
    selling_markets(game, system_symbol, trade_symbol)
    |> Enum.sort_by(fn {_, price} -> price end, :desc)
    |> List.first()
  end

  def surveys(game, waypoint_symbol) do
    game.surveys
    |> Map.get(waypoint_symbol, [])
    |> Enum.filter(fn survey ->
      {:ok, expiration, _} = DateTime.from_iso8601(survey["expiration"])

      DateTime.before?(DateTime.utc_now(), expiration)
    end)
  end

  def trading_pairs(game, system_symbol) do
    markets =
      Map.get(game.markets, system_symbol, %{})
      |> Enum.map(fn {_waypoint_symbol, market} ->
        market
      end)

    Enum.flat_map(markets, fn start_market ->
      Map.get(start_market, "tradeGoods", [])
      |> Enum.filter(fn t -> t["purchasePrice"] > 0 end)
      |> Enum.flat_map(fn start_trade_good ->
        Enum.flat_map(markets, fn end_market ->
          Map.get(end_market, "tradeGoods", [])
          |> Enum.filter(fn end_trade_good ->
            start_trade_good["symbol"] == end_trade_good["symbol"] &&
              end_trade_good["sellPrice"] > start_trade_good["purchasePrice"]
          end)
          |> Enum.map(fn end_trade_good ->
            start_wp = waypoint(game, system_symbol, Map.fetch!(start_market, "symbol"))
            end_wp = waypoint(game, system_symbol, Map.fetch!(end_market, "symbol"))

            %ShipTask{
              name: :trade,
              args: %{
                trade_symbol: start_trade_good["symbol"],
                start_wp: start_wp["symbol"],
                end_wp: end_wp["symbol"],
                volume: min(end_trade_good["tradeVolume"], start_trade_good["tradeVolume"]),
                profit: end_trade_good["sellPrice"] - start_trade_good["purchasePrice"],
                credits_required: start_trade_good["purchasePrice"],
                roi: end_trade_good["sellPrice"] / start_trade_good["purchasePrice"],
                distance: :math.sqrt(:math.pow(start_wp["x"] - end_wp["x"], 2) + :math.pow(start_wp["y"] - end_wp["y"], 2))
              }
            }
          end)
        end)
      end)
    end)
  end

  def distance_between(game, wp_a, wp_b) when is_binary(wp_a) and is_binary(wp_b) do
    wp_a = waypoint(game, wp_a)
    wp_b = waypoint(game, wp_b)


    :math.sqrt(:math.pow(wp_a["x"] - wp_b["x"], 2) + :math.pow(wp_a["y"] - wp_b["y"], 2))
  end
end
