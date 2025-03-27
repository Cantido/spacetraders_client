defmodule SpacetradersClient.Game do
  alias SpacetradersClient.LedgerServer
  alias Motocho.Journal
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
    waypoints: %{},
    markets: %{},
    shipyards: %{},
    surveys: %{},
    extractions: %{},
    construction_sites: %{}
  ]

  def new(client) do
    %__MODULE__{client: client}
  end

  def load_agent(game) do
    case Agents.my_agent(game.client) do
      {:ok, %{status: 200, body: body}} ->
        {:ok, %{game | agent: body["data"]}}

      {:ok, resp} ->
        {:error, resp.body}

      {:error, reason} ->
        {:error, reason}
    end
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
    {:ok, %{status: 200, body: body}} =
      Systems.get_waypoint(game.client, system_symbol, waypoint_symbol)

    game
    |> Map.update!(:systems, fn systems ->
      systems
      |> Map.put_new(system_symbol, %{})
      |> Map.update!(system_symbol, &Map.put(&1, waypoint_symbol, body["data"]))
    end)
  end

  def load_market!(game, system_symbol, waypoint_symbol) do
    {:ok, %{status: 200, body: body}} =
      Systems.get_market(game.client, system_symbol, waypoint_symbol)

    put_in(
      game,
      [
        Access.key(:markets),
        Access.key(system_symbol, %{}),
        waypoint_symbol
      ],
      body["data"]
    )
  end

  def load_all_waypoints!(game) do
    game.fleet
    |> Enum.map(fn {_ship_symbol, ship} ->
      ship["nav"]["systemSymbol"]
    end)
    |> Enum.uniq()
    |> Enum.flat_map(&fetch_waypoints(game.client, &1))
    |> Enum.reduce(game, fn waypoint, game ->
      put_in(game, [Access.key(:waypoints), waypoint["symbol"]], waypoint)
    end)
  end

  def load_shipyards!(game) do
    game.waypoints
    |> Enum.map(fn {_wp_symbol, wp} ->
      wp
    end)
    |> Enum.filter(fn waypoint ->
      traits = Enum.map(waypoint["traits"], fn t -> t["symbol"] end)

      "SHIPYARD" in traits
    end)
    |> Enum.reduce(game, fn waypoint, game ->
      load_shipyard!(game, waypoint["systemSymbol"], waypoint["symbol"])
    end)
  end

  def load_shipyard!(game, system_symbol, waypoint_symbol) do
    {:ok, %{status: 200, body: body}} =
      Systems.get_shipyard(game.client, system_symbol, waypoint_symbol)

    put_in(
      game,
      [
        Access.key(:shipyards),
        Access.key(system_symbol, %{}),
        waypoint_symbol
      ],
      body["data"]
    )
  end

  defp fetch_waypoints(client, system_symbol, page \\ 1, waypoints \\ []) do
    case Systems.list_waypoints(client, system_symbol, page: page) do
      {:ok, %{status: 200, body: body}} ->
        waypoints = body["data"] ++ waypoints

        if body["meta"]["total"] > Enum.count(waypoints) do
          fetch_waypoints(client, system_symbol, page + 1, waypoints)
        else
          waypoints
        end

      err ->
        Logger.error("Failed to fetch waypoint list: #{inspect(err)}")
        []
    end
  end

  def load_markets!(game) do
    game.waypoints
    |> Enum.map(fn {_wp_symbol, wp} ->
      wp
    end)
    |> Enum.filter(fn waypoint ->
      traits = Enum.map(waypoint["traits"], fn t -> t["symbol"] end)

      "MARKETPLACE" in traits
    end)
    |> Enum.reduce(game, fn waypoint, game ->
      load_market!(game, waypoint["systemSymbol"], waypoint["symbol"])
    end)
  end

  def load_construction_sites!(game) do
    game.waypoints
    |> Enum.map(fn {_wp_symbol, wp} ->
      wp
    end)
    |> Enum.filter(fn waypoint ->
      waypoint["isUnderConstruction"]
    end)
    |> Enum.reduce(game, fn waypoint, game ->
      load_construction_site!(game, waypoint["symbol"])
    end)
  end

  def load_construction_site!(game, waypoint_symbol) do
    system_symbol = system_symbol(waypoint_symbol)

    {:ok, %{status: 200, body: body}} =
      Systems.get_construction_site(game.client, system_symbol, waypoint_symbol)

    put_in(
      game,
      [
        Access.key(:construction_sites),
        waypoint_symbol
      ],
      body["data"]
    )
  end

  @doc """
  Returns the credit value of all ships in the agent's fleet.

  Ship prices are averaged from all known shipyards.
  """
  def fleet_value(game) do
    Enum.map(game.fleet, fn {_id, ship} ->
      case ship["registration"]["role"] do
        "EXCAVATOR" -> "SHIP_MINING_DRONE"
        "TRANSPORT" -> "SHIP_LIGHT_SHUTTLE"
        "SATELLITE" -> "SHIP_PROBE"
        _ -> nil
      end
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.frequencies()
    |> Enum.map(fn {ship_type, count} ->
      price = average_ship_price(game, ship_type)
      {price, count}
    end)
    |> Enum.reject(&is_nil(elem(&1, 0)))
    |> Enum.map(fn {price, count} -> price * count end)
    |> Enum.sum()
  end

  @doc """
  Returns the credit value of all merchandise in the agent's fleet's cargo holds.

  Merchandise prices are averaged over the selling price from all known markets.
  """
  def merchandise_value(game) do
    Enum.flat_map(game.fleet, fn {_id, ship} ->
      ship["cargo"]["inventory"]
    end)
    |> Enum.map(fn item ->
      price_per_unit =
        average_selling_price(game, item["symbol"])

      %{
        trade_symbol: item["symbol"],
        units: item["units"],
        total_cost: price_per_unit * item["units"]
      }
    end)
  end

  def add_extraction(game, waypoint_symbol, extraction) do
    update_in(
      game,
      [Access.key(:extractions), Access.key(waypoint_symbol, [])],
      &[extraction | &1]
    )
    |> tap(fn game ->
      average_extraction_yield(game)
    end)
  end

  def average_extraction_yield(game, waypoint_symbol) do
    # TODO: Factor in laser/siphon strength

    waypoint_extractions =
      game.extractions
      |> Map.get(waypoint_symbol, [])

    extraction_count = Enum.count(waypoint_extractions)

    waypoint_extractions
    |> Enum.map(&Map.get(&1, "yield"))
    |> Enum.reduce(%{}, fn yield, total_yield ->
      total_yield
      |> Map.put_new(yield["symbol"], 0)
      |> Map.update!(yield["symbol"], &(&1 + yield["units"]))
    end)
    |> Map.new(fn {symbol, units} ->
      avg_units = units / extraction_count

      {symbol, avg_units}
    end)
  end

  def average_extraction_yield(game) do
    # TODO: Factor in laser/siphon strength

    extractions =
      Map.values(game.extractions)
      |> List.flatten()

    extraction_count = Enum.count(extractions)

    extractions
    |> Enum.map(&Map.get(&1, "yield"))
    |> Enum.reduce(%{}, fn yield, total_yield ->
      total_yield
      |> Map.put_new(yield["symbol"], 0)
      |> Map.update!(yield["symbol"], &(&1 + yield["units"]))
    end)
    |> Map.new(fn {symbol, units} ->
      avg_units = units / extraction_count

      {symbol, avg_units}
    end)
  end

  def average_extraction_value(game, waypoint_symbol) do
    average_extraction_yield(game, waypoint_symbol)
    |> Enum.map(fn {trade_symbol, units} ->
      value = average_selling_price(game, system_symbol(waypoint_symbol), trade_symbol)

      value * units
    end)
    |> Enum.sum()
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

  def waypoint(game, _system_symbol, waypoint_symbol) do
    game.waypoints
    |> Map.get(waypoint_symbol)
  end

  def waypoints(game, system_symbol) do
    game.waypoints
    |> Enum.filter(fn {_symbol, wp} ->
      wp["systemSymbol"] == system_symbol
    end)
  end

  def waypoints(game) do
    Map.values(game.waypoints)
  end

  def markets(game, system_symbol) do
    game.markets
    |> Map.get(system_symbol, %{})
    |> Map.values()
  end

  def markets(game) do
    game.markets
    |> Map.values()
    |> Enum.flat_map(&Map.values/1)
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
      trade_good =
        Enum.find(Map.get(market, "tradeGoods", []), fn t -> t["symbol"] == trade_symbol end)

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
      trade_good =
        Enum.find(Map.get(market, "tradeGoods", []), fn t -> t["symbol"] == trade_symbol end)

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
      count = Enum.count(prices)

      if count > 0 do
        Enum.sum(prices) / Enum.count(prices)
      else
        nil
      end
    end)
  end

  def average_selling_price(game, trade_symbol) do
    selling_markets(game, trade_symbol)
    |> Enum.map(fn {_, price} -> price end)
    |> then(fn prices ->
      if Enum.empty?(prices) do
        0
      else
        Enum.sum(prices) / Enum.count(prices)
      end
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

  def ships_for_purchase(game, ship_type) do
    game.shipyards
    |> Map.values()
    |> Enum.flat_map(&Map.values/1)
    |> Enum.map(fn shipyard ->
      ship =
        Enum.find(Map.get(shipyard, "ships", []), fn s -> s["type"] == ship_type end)

      {shipyard, ship}
    end)
    |> Enum.reject(fn {_, ship} -> is_nil(ship) end)
    |> Enum.reject(fn {_, ship} -> ship["purchasePrice"] == 0 end)
  end

  def average_ship_price(game, ship_type) do
    available =
      ships_for_purchase(game, ship_type)

    price_sum =
      Enum.map(available, fn {_shipyard, ship} ->
        ship["purchasePrice"]
      end)
      |> Enum.sum()

    if Enum.count(available) > 0 do
      price_sum / Enum.count(available)
    else
      nil
    end
  end

  def purchase_markets(game, system_symbol, trade_symbol) do
    game.markets
    |> Map.get(system_symbol, %{})
    |> Enum.map(fn {_symbol, market} ->
      trade_good =
        Enum.find(Map.get(market, "tradeGoods", []), fn t -> t["symbol"] == trade_symbol end)

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
      trade_good =
        Enum.find(Map.get(market, "tradeGoods", []), fn t -> t["symbol"] == trade_symbol end)

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
    |> avg()
  end

  def average_purchase_price(game, trade_symbol) do
    purchase_markets(game, trade_symbol)
    |> Enum.map(fn {_, price} -> price end)
    |> avg()
  end

  defp avg(nums, default \\ nil) do
    count = Enum.count(nums)

    if count > 0 do
      Enum.sum(nums) / count
    else
      default
    end
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

            ShipTask.new(
              :trade,
              %{
                trade_symbol: start_trade_good["symbol"],
                start_wp: start_wp["symbol"],
                end_wp: end_wp["symbol"],
                volume: min(end_trade_good["tradeVolume"], start_trade_good["tradeVolume"]),
                profit: end_trade_good["sellPrice"] - start_trade_good["purchasePrice"],
                credits_required: start_trade_good["purchasePrice"],
                revenue: end_trade_good["sellPrice"],
                roi: end_trade_good["sellPrice"] / start_trade_good["purchasePrice"],
                distance:
                  :math.sqrt(
                    :math.pow(start_wp["x"] - end_wp["x"], 2) +
                      :math.pow(start_wp["y"] - end_wp["y"], 2)
                  )
              }
            )
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
    market_vis = market_visibility_actions(game)
    construction_actions = construction_actions(game)

    resource_extractions ++
      resource_pickups ++ market_actions ++ market_vis ++ construction_actions
  end

  defp resource_actions(waypoint) do
    cond do
      waypoint["type"] in ~w(ASTEROID ASTEROID_FIELD ENGINEERED_ASTEROID) ->
        task =
          ShipTask.new(
            :mine,
            %{waypoint_symbol: waypoint["symbol"]},
            [
              &Ship.has_mining_laser?/1,
              &Ship.has_cargo_capacity?/1
            ]
          )

        [task]

      waypoint["type"] in ~w(GAS_GIANT) ->
        task =
          ShipTask.new(
            :siphon_resources,
            %{waypoint_symbol: waypoint["symbol"]},
            [
              &Ship.has_gas_siphon?/1,
              &Ship.has_cargo_capacity?/1
            ]
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
      selling_markets(
        game,
        system_symbol(pickup_task.args.start_wp),
        pickup_task.args.trade_symbol
      )
      |> Enum.map(fn {market, price} ->
        volume = Enum.find(market["tradeGoods"], fn t -> t["symbol"] end)["tradeVolume"]

        ShipTask.variation(pickup_task, %{
          volume: volume,
          price: price,
          end_wp: market["symbol"]
        })
      end)
    end)

    # Disallow the mining ships themselves from picking up anything

    |> Enum.map(fn pickup_task ->
      Enum.reduce(pickup_task.args.ship_pickups, pickup_task, fn {ship_symbol, _units},
                                                                 pickup_task ->
        pickup_task
        |> ShipTask.add_condition(fn ship -> ship["symbol"] != ship_symbol end)
        |> ShipTask.add_condition(fn ship -> ship["registration"]["role"] != "EXCAVATOR" end)
      end)
    end)
  end

  defp market_visibility_actions(game) do
    satellites_at_wp =
      game
      |> markets()
      |> Enum.map(fn market ->
        market["symbol"]
      end)
      |> Map.new(fn waypoint_symbol ->
        satellites =
          game.fleet
          |> Enum.filter(fn {_symbol, ship} ->
            ship["nav"]["waypointSymbol"] == waypoint_symbol &&
              ship["registration"]["role"] == "SATELLITE"
          end)
          |> Enum.map(fn {_symbol, ship} ->
            ship
          end)

        {waypoint_symbol, satellites}
      end)

    duplicate_sat_symbols =
      satellites_at_wp
      |> Enum.flat_map(fn {_waypoint, sats} ->
        Enum.drop(sats, 1)
      end)
      |> Enum.map(fn sat ->
        sat["symbol"]
      end)

    satellites_at_wp
    |> Map.filter(fn {_wp, satellites} ->
      Enum.count(satellites) == 0
    end)
    |> Enum.map(fn {waypoint_symbol, _sats} ->
      ShipTask.new(
        :goto,
        %{waypoint_symbol: waypoint_symbol},
        [
          fn ship -> ship["symbol"] in duplicate_sat_symbols end,
          fn ship -> ship["registration"]["role"] == "SATELLITE" end
        ]
      )
    end)
  end

  defp construction_actions(game) do
    game.construction_sites
    |> Enum.map(fn {_symbol, site} -> site end)
    |> Enum.reject(fn site -> site["isComplete"] end)
    |> Enum.flat_map(fn site ->
      Enum.map(site["materials"], fn material ->
        ShipTask.new(
          :deliver_construction_materials,
          %{
            waypoint_symbol: site["symbol"],
            trade_symbol: material["tradeSymbol"],
            remaining_units: material["required"] - material["fulfilled"],
            required_units: material["required"],
            fulfilled_units: material["fulfilled"]
          }
        )
      end)
      |> Enum.reject(fn task -> task.args.remaining_units == 0 end)
    end)
  end

  def update_construction_site!(game, waypoint_symbol, update_fun) do
    update_in(
      game,
      [Access.key(:construction_sites), Access.key(waypoint_symbol, nil)],
      update_fun
    )
  end
end
