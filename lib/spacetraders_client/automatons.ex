defmodule SpacetradersClient.Automatons do

  alias SpacetradersClient.Utility
  alias SpacetradersClient.ShipTask
  alias SpacetradersClient.Behaviors
  alias SpacetradersClient.Game
  alias SpacetradersClient.Ship
  alias SpacetradersClient.ShipAutomaton

  alias Taido.Node

  require Logger

  @system "X1-BU22"
  @mining_wp "X1-BU22-DA5F"
  @market_wp "X1-BU22-H54"

  @average_fuel_price 1.5 # per fuel unit, not market unit!!

  def mining_ship(game, ship_symbol) do
    ShipAutomaton.new(game, ship_symbol, &mining_phase/2, &Behaviors.for_task/1)
  end

  defp mining_phase(%Game{} = game, ship_symbol) do
    ship = Game.ship(game, ship_symbol)
    waypoint = Game.waypoint(game, ship["nav"]["waypointSymbol"])

    cond do
      waypoint["type"] in ~w(ASTEROID ASTEROID_FIELD ENGINEERED_ASTEROID) &&
        ship["cargo"]["units"] < ship["cargo"]["capacity"] - 3 ->

        ShipTask.new(:mine, %{
          waypoint_symbol: ship["nav"]["waypointSymbol"]
        })
      true ->
        ShipTask.new(:idle)
    end
  end

  def hauling_ship(game, ship_symbol) do
    ShipAutomaton.new(game, ship_symbol, &hauling_phase/2, &hauling_behavior/1)
  end

  defp hauling_phase(%Game{} = game, ship_symbol) do
    ship = Game.ship(game, ship_symbol)
    market = Game.market(game, @system, @market_wp)

    cond do
      Enum.any?(Ship.cargo_to_jettison(ship, market)) ->
        :jettison
      ship["nav"]["waypointSymbol"] == @market_wp && ship["cargo"]["units"] > 0 ->
        :selling
      ship["cargo"]["units"] < ship["cargo"]["capacity"] - 3 ->
        :loading
      true ->
        :selling
    end
  end

  defp hauling_behavior(:loading) do
    Node.sequence([
      Behaviors.travel_to_waypoint(@mining_wp),
      Behaviors.wait_for_transit(),
      Behaviors.enter_orbit()
    ])
  end

  defp hauling_behavior(:selling) do
    Node.sequence([
      Behaviors.travel_to_waypoint(@market_wp),
      Behaviors.wait_for_transit(),
      Behaviors.dock_ship()
      # Behaviors.sell_cargo_item()
    ])
  end

  defp hauling_behavior(:jettison) do
    Node.sequence([
      Behaviors.enter_orbit(),
      Behaviors.jettison_cargo()
    ])
  end

  def surveyor_ship(game, ship_symbol) do
    ShipAutomaton.new(game, ship_symbol, &surveyor_phase/2, &surveyor_behavior/1)
  end

  def surveyor_phase(%Game{}, _ship_symbol) do
    :surveying
  end

  def surveyor_behavior(:surveying) do
    Node.sequence([
      Behaviors.travel_to_waypoint(@mining_wp),
      Behaviors.wait_for_transit(),
      Behaviors.enter_orbit(),
      Behaviors.wait_for_ship_cooldown(),
      Behaviors.create_survey()
    ])
  end

  def trading_ship(game, ship_symbol) do
    ShipAutomaton.new(game, ship_symbol, &trading_phase/2, &Behaviors.for_task/1)
  end

  def trading_phase(%Game{} = game, ship_symbol) do
    ship = Game.ship(game, ship_symbol)

    mining_pickup_tasks =

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
      # Also update the units to transport based on available cargo and market volume.

      |> Enum.flat_map(fn pickup_task ->
        Game.selling_markets(game, Game.system_symbol(pickup_task.args.start_wp), pickup_task.args.trade_symbol)
        |> Enum.map(fn {market, price} ->
          volume = Enum.find(market["tradeGoods"], fn t -> t["symbol"] end)["tradeVolume"]
          available_capacity =
            (ship["cargo"]["capacity"] - ship["cargo"]["units"])
            |> min(volume)

          {_remaining_cargo_space, ship_pickups} =
            Enum.reduce_while(pickup_task.args.ship_pickups, {available_capacity, %{}}, fn {ship_symbol, ship_units}, {cargo_space, pickups} ->
              units_to_take = min(cargo_space, ship_units)
              remaining_cargo_space = cargo_space - units_to_take

              continue =
                if remaining_cargo_space > 0 do
                  :cont
                else
                  :halt
                end

              {continue, {remaining_cargo_space, Map.put(pickups, ship_symbol, units_to_take)}}
            end)

          units = Enum.map(ship_pickups, fn {_symbol, units} -> units end) |> Enum.sum()
          total_profit = price * units

          args =
            Map.merge(pickup_task.args, %{
              ship_pickups: ship_pickups,
              price: price,
              end_wp: market["symbol"],
              total_profit: total_profit
            })

          %{pickup_task | args: args}
        end)
      end)

      # Multiply each task by the different flight modes the ship can take to the pickup site.
      # adding fuel & time costs, and updating total profit accordingly to the task args.

      |> Enum.flat_map(fn pickup_task ->
        proximity = Game.distance_between(game, ship["nav"]["waypointSymbol"], pickup_task.args.start_wp)

        Ship.possible_travel_modes(ship, proximity)
        |> Enum.map(fn start_flight_mode ->

          start_fuel_consumption = Ship.fuel_cost(proximity) |> Map.fetch!(start_flight_mode)
          start_leg_time = Ship.travel_time(ship, proximity) |> Map.fetch!(start_flight_mode)

          fuel_cost = @average_fuel_price * start_fuel_consumption
          time_required = start_leg_time
          total_profit = pickup_task.args.total_profit - fuel_cost

          args =
            Map.merge(pickup_task.args, %{
              start_flight_mode: start_flight_mode,
              time_required: time_required,
              total_profit: total_profit,
            })

          %{pickup_task | args: args}
        end)
      end)

      # Multiply each task by the different flight modes the ship can take to the selling site,
      # adding fuel & time costs, and updating total profit accordingly to the task args.

      |> Enum.flat_map(fn pickup_task ->
        distance = Game.distance_between(game, pickup_task.args.start_wp, pickup_task.args.end_wp)

        Ship.possible_travel_modes(ship, distance)
        |> Enum.map(fn transport_flight_mode ->

          transport_fuel_consumption = Ship.fuel_cost(distance) |> Map.fetch!(transport_flight_mode)
          transport_leg_time = Ship.travel_time(ship, distance) |> Map.fetch!(transport_flight_mode)

          fuel_cost = @average_fuel_price * transport_fuel_consumption
          time_required = pickup_task.args.time_required + transport_leg_time
          total_profit = pickup_task.args.total_profit - fuel_cost

          args =
            Map.merge(pickup_task.args, %{
              transport_flight_mode: transport_flight_mode,
              time_required: time_required,
              total_profit: total_profit,
            })

          %{pickup_task | args: args}
        end)
      end)

      # Calculate profit over time for every task, adding it to the task args.

      |> Enum.map(fn pickup_task ->
          args =
            Map.merge(pickup_task.args, %{
              profit_over_time: pickup_task.args.total_profit / pickup_task.args.time_required
            })

          %{pickup_task | args: args}
      end)

    sell_tasks =
      Enum.flat_map(ship["cargo"]["inventory"], fn item ->
        Game.selling_markets(game, ship["nav"]["systemSymbol"], item["symbol"])
        |> Enum.flat_map(fn {market, price} ->
          distance = Game.distance_between(game, ship["nav"]["waypointSymbol"], market["symbol"])

          Ship.possible_travel_modes(ship, distance)
          |> Enum.map(fn flight_mode ->
            units =
              market
              |> Map.fetch!("tradeGoods")
              |> Enum.find(fn t -> t["symbol"] end)
              |> Map.fetch!("tradeVolume")
              |> min(item["units"])

            fuel_used = Ship.fuel_cost(distance) |> Map.fetch!(flight_mode)
            fuel_cost = @average_fuel_price * fuel_used

            travel_time = Ship.travel_time(ship, distance) |> Map.fetch!(flight_mode)

            total_profit = (units * price) - fuel_cost
            profit_over_time = total_profit / travel_time

            ShipTask.new(
              :selling,
              %{
                waypoint_symbol: market["symbol"],
                trade_symbol: item["symbol"],
                price: price,
                units: units,
                total_profit: total_profit,
                flight_mode: flight_mode,
                profit_over_time: profit_over_time
              }
            )
          end)
        end)
      end)

    trade_tasks =
      Game.trading_pairs(game, ship["nav"]["systemSymbol"])
      |> Enum.flat_map(fn trade_task ->
        proximity = Game.distance_between(game, ship["nav"]["waypointSymbol"], trade_task.args.start_wp)

        Ship.possible_travel_modes(ship, proximity)
        |> Enum.flat_map(fn start_flight_mode ->
          Ship.possible_travel_modes(ship, trade_task.args.distance)
          |> Enum.map(fn transport_flight_mode ->

            cargo_space = ship["cargo"]["capacity"] - ship["cargo"]["units"]

            units =
              (max(game.agent["credits"] - 5_000, 0) / trade_task.args.credits_required)
              |> min(cargo_space)
              |> min(trade_task.args.volume)
              |> trunc()

            start_fuel_consumption = Ship.fuel_cost(proximity) |> Map.fetch!(start_flight_mode)
            start_leg_time = Ship.travel_time(ship, proximity) |> Map.fetch!(start_flight_mode)

            transport_fuel_consumption = Ship.fuel_cost(trade_task.args.distance) |> Map.fetch!(transport_flight_mode)
            transport_leg_time = Ship.travel_time(ship, trade_task.args.distance) |> Map.fetch!(transport_flight_mode)

            fuel_cost = @average_fuel_price * (start_fuel_consumption + transport_fuel_consumption)
            time_required = start_leg_time + transport_leg_time
            total_profit = (units * trade_task.args.profit) - fuel_cost

            args =
              Map.merge(trade_task.args, %{
                units: units,
                total_profit: total_profit,
                profit_over_time: total_profit / time_required,
                start_flight_mode: start_flight_mode,
                transport_flight_mode: transport_flight_mode
              })

            %{trade_task | args: args}
          end)
        end)
      end)
      |> Enum.reject(fn task -> task.args.units == 0 end)

    best_task_score =
      (sell_tasks ++ trade_tasks ++ mining_pickup_tasks)
      |> tap(fn tasks ->
        Logger.debug("Ship #{ship_symbol} has #{Enum.count(tasks)} tasks to choose from.")
      end)
      |> Enum.map(fn task ->
        {task, Utility.score(game, ship_symbol, task)}
      end)
      |> Enum.reject(fn {_task, score} -> score < 0.05 end)
      |> Enum.sort_by(&elem(&1, 1), :desc)
      |> Enum.max_by(fn {_task, score} -> score end, fn -> nil end)

    if best_task_score do
      {best_task, utility_score} = best_task_score
      Logger.debug("Ship #{ship_symbol} chose task #{inspect best_task.name} with score #{utility_score} and this defintion:\n#{inspect best_task, pretty: true}")
      best_task
    end
  end
end
