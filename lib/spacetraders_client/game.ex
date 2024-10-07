defmodule SpacetradersClient.Game do
  alias SpacetradersClient.Ship
  alias SpacetradersClient.ShipTask
  alias SpacetradersClient.Agents
  alias SpacetradersClient.Fleet
  alias SpacetradersClient.Systems

  alias Motocho.Ledger

  require Logger

  @enforce_keys [:client]
  defstruct [
    :client,
    agent: %{},
    fleet: %{},
    systems: %{},
    markets: %{},
    shipyards: %{},
    surveys: %{},
    transactions: [],
    ledger: nil
  ]

  def new(client) do
    %__MODULE__{client: client}
  end

  def load_agent!(game) do
    {:ok, %{status: 200, body: body}} = Agents.my_agent(game.client)

    %{game | agent: body["data"]}
  end

  def load_fleet!(game, page \\ 1) do
    {:ok, %{status: 200, body: body}} = Fleet.list_ships(game.client, page: page)

    fleet =
      if page == 1 do
        %{}
      else
        game.fleet
      end
      |> Map.merge(
        Map.new(body["data"], fn ship ->
          {ship["symbol"], ship}
        end)
      )

    if Enum.count(game.fleet) < body["meta"]["total"] do
      %{game | fleet: fleet}
      |> load_fleet!(page + 1)
    else
      %{game | fleet: fleet}
    end
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
    |> then(fn game ->
      if game.ledger do
        game
      else
        reset_ledger(game)
      end
    end)

  end

  def reset_ledger(game) do
    ledger =
      Ledger.new()
      |> Ledger.open_account("Cash", :assets)
      |> Ledger.open_account("Merchandise", :assets)
      |> Ledger.open_account("Sales", :revenue)
      |> Ledger.open_account("Natural Resources", :revenue)
      |> Ledger.open_account("Starting Balances", :revenue)
      |> Ledger.open_account("Cost of Merchandise Sold", :expenses)
      |> Ledger.open_account("Fuel", :expenses)
      |> Ledger.post(
        DateTime.utc_now(),
        "Starting Credits Balance",
        "Cash",
        "Starting Balances",
        game.agent["credits"]
      )

    starting_merchandise_balance =
      Enum.flat_map(game.fleet, fn {_id, ship} ->
        ship["cargo"]["inventory"]
      end)
      |> Enum.map(fn item ->
        price = average_purchase_price(game, item["symbol"])

        price * item["units"]
      end)
      |> Enum.sum()

    ledger =
      Ledger.post(
        ledger,
        DateTime.utc_now(),
        "Starting Merchandise Balance",
        "Merchandise",
        "Starting Balances",
        starting_merchandise_balance
      )

    %{game | ledger: ledger}
  end

  def add_transaction(game, transaction) do
    Map.update!(game, :transactions, fn txs -> [transaction | txs] end)
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

  def update_ledger(%__MODULE__{} = game, update_fun) do
    Map.update!(game, :ledger, fn ledger ->
      %Ledger{} = update_fun.(ledger)
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

  def waypoints(game) do
    Enum.flat_map(game.systems, fn {_, waypoints} -> Map.values(waypoints) end)
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

  def selling_markets(game, trade_symbol) do
    game.markets
    |> Enum.flat_map(fn {_, markets} -> Map.values(markets) end)
    |> Enum.map(fn market ->
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

  def average_selling_price(game, system_symbol, trade_symbol) do
    selling_markets(game, system_symbol, trade_symbol)
    |> Enum.map(fn {_, price} -> price end)
    |> then(fn prices ->
      Enum.sum(prices) / Enum.count(prices)
    end)
  end

  def best_selling_market_price(game, system_symbol, trade_symbol) do
    selling_markets(game, system_symbol, trade_symbol)
    |> Enum.sort_by(fn {_, price} -> price end, :desc)
    |> List.first()
  end

  def best_selling_market_price(game, trade_symbol) do
    selling_markets(game, trade_symbol)
    |> Enum.sort_by(fn {_, price} -> price end, :desc)
    |> List.first()
  end

  def purchase_markets(game, system_symbol, trade_symbol) do
    game.markets
    |> Map.get(system_symbol, %{})
    |> Enum.map(fn {_symbol, market} ->
      trade_good = Enum.find(Map.get(market, "tradeGoods", []), fn t -> t["symbol"] == trade_symbol end)

      if trade_good do
        {market, trade_good["purchasePrice"]}
      else
        {market, 0}
      end
    end)
    |> Enum.reject(fn {_, price} -> is_nil(price) end)
    |> Enum.reject(fn {_, price} -> price == 0 end)
  end

  def purchase_markets(game, trade_symbol) do
    game.markets
    |> Enum.flat_map(fn {_, markets} -> Map.values(markets) end)
    |> Enum.map(fn market ->
      trade_good = Enum.find(Map.get(market, "tradeGoods", []), fn t -> t["symbol"] == trade_symbol end)

      if trade_good do
        {market, trade_good["purchasePrice"]}
      else
        {market, 0}
      end
    end)
    |> Enum.reject(fn {_, price} -> is_nil(price) end)
    |> Enum.reject(fn {_, price} -> price == 0 end)
  end

  def average_purchase_price(game, system_symbol, trade_symbol) do
    purchase_markets(game, system_symbol, trade_symbol)
    |> Enum.map(fn {_, price} -> price end)
    |> then(fn prices ->
      Enum.sum(prices) / Enum.count(prices)
    end)
  end

  def average_purchase_price(game, trade_symbol) do
    purchase_markets(game, trade_symbol)
    |> Enum.map(fn {_, price} -> price end)
    |> then(fn prices ->
      Enum.sum(prices) / Enum.count(prices)
    end)
  end

  def best_purchase_market_price(game, system_symbol, trade_symbol) do
    purchase_markets(game, system_symbol, trade_symbol)
    |> Enum.sort_by(fn {_, price} -> price end, :asc)
    |> List.first()
  end

  def best_purchase_market_price(game, trade_symbol) do
    purchase_markets(game, trade_symbol)
    |> Enum.sort_by(fn {_, price} -> price end, :asc)
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

  def market_actions(game) do
    markets =
      Enum.flat_map(game.markets, fn {_system_symbol, markets} ->
        Map.values(markets)
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
            start_wp = waypoint(game, Map.fetch!(start_market, "symbol"))
            end_wp = waypoint(game, Map.fetch!(end_market, "symbol"))

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

  def actions(%__MODULE__{} = game) do
    resource_extractions =
      waypoints(game)
      |> Enum.flat_map(fn waypoint ->
        resource_actions(waypoint)
      end)

    resource_pickups = resource_pickup_actions(game)

    market_actions = market_actions(game)

    resource_extractions ++ resource_pickups ++ market_actions
  end

  defp resource_actions(waypoint) do
    cond do
      waypoint["type"] in ~w(ASTEROID ASTEROID_FIELD ENGINEERED_ASTEROID) ->
        task =
          ShipTask.new(
            :mine,
            %{waypoint_symbol: waypoint["symbol"]},
            [&Ship.has_mining_laser?/1, &Ship.has_cargo_capacity?/1]
          )

        [task]

      waypoint["type"] in ~w(GAS_GIANT) ->
        task =
          ShipTask.new(
            :siphon_resources,
            %{waypoint_symbol: waypoint["symbol"]},
            [&Ship.has_gas_siphon?/1, &Ship.has_cargo_capacity?/1]
          )

        [task]
      true ->
        []
    end
  end

  defp resource_pickup_actions(game) do
    # First phase of this pipeline: collecting all excavators and their contents
    # into maps by waypoint, so we can pick up all of one item at once.
    # This will make it easier to find buyers.

    Enum.filter(game.fleet, fn {_, mining_ship} ->
      mining_ship["registration"]["role"] == "EXCAVATOR" &&
        mining_ship["nav"]["status"] == "IN_ORBIT"
    end)
    |> Enum.map(fn {_symbol, ship} -> ship end)
    |> Enum.group_by(fn ship -> ship["nav"]["waypointSymbol"] end)
    |> Enum.map(fn {waypoint_symbol, ships} ->
      # Example of the data structure I'm trying to build, one for each waypoint:
      #
      # %{
      #   "IRON_ORE" => %{
      #     "COSMIC-ROSE-5" => 5
      #   }
      # }
      resources_available =
        Enum.reduce(ships, %{}, fn ship, resources ->
          Enum.reduce(ship["cargo"]["inventory"], resources, fn item, resources ->
            resources
            |> Map.put_new(item["symbol"], %{})
            |> Map.update!(item["symbol"], fn resource ->
              Map.put(resource, ship["symbol"], item["units"])
            end)
          end)
        end)

      {waypoint_symbol, resources_available}
    end)

    # Second phase: Turning excavator content groups into pickup tasks

    |> Enum.flat_map(fn {waypoint_symbol, resources_available} ->
      Enum.map(resources_available, fn {trade_symbol, ships_carrying} ->
        ShipTask.new(
          :pickup,
          %{
            start_wp: waypoint_symbol,
            trade_symbol: trade_symbol,
            ship_pickups: ships_carrying
          }
        )
      end)
    end)

    # Multiply the pickup tasks by the material buyers available in the system,
    # adding the buyer market and total profit to the task args.

    |> Enum.flat_map(fn pickup_task ->
      selling_markets(game, system_symbol(pickup_task.args.start_wp), pickup_task.args.trade_symbol)
      |> Enum.map(fn {market, price} ->
        volume = Enum.find(market["tradeGoods"], fn t -> t["symbol"] end)["tradeVolume"]

        args =
          Map.merge(pickup_task.args, %{
            volume: volume,
            price: price,
            end_wp: market["symbol"],
          })

        %{pickup_task | args: args}
      end)
    end)

    # Disallow the mining ships themselves from picking up their own materials

    |> Enum.map(fn pickup_task ->
      Enum.reduce(pickup_task.args.ship_pickups, pickup_task, fn {ship_symbol, _units}, pickup_task ->
        condition = fn ship -> ship["symbol"] != ship_symbol end

        conditions = [condition | pickup_task.conditions]

        %{pickup_task | conditions: conditions}
      end)
    end)
  end
end
