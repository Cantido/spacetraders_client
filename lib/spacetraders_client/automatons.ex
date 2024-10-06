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

  @average_fuel_price 2 # per fuel unit, not market unit!!

  def mining_ship(game, ship_symbol) do
    ShipAutomaton.new(game, ship_symbol, &mining_phase/2)
  end

  defp mining_phase(%Game{} = game, ship_symbol) do
    ship = Game.ship(game, ship_symbol)
    waypoint = Game.waypoint(game, ship["nav"]["waypointSymbol"])
    mounts = Enum.map(ship["mounts"], fn m -> m["symbol"] end)

    cond do
      waypoint["type"] in ~w(ASTEROID ASTEROID_FIELD ENGINEERED_ASTEROID) &&
        Enum.any?(mounts, fn mount -> mount in ~w(MOUNT_MINING_LASER_I MOUNT_MINING_LASER_II MOUNT_MINING_LASER_III) end) &&
        ship["cargo"]["units"] < ship["cargo"]["capacity"] - 3 ->

        ShipTask.new(:mine, %{
          waypoint_symbol: ship["nav"]["waypointSymbol"]
        })

      waypoint["type"] in ~w(GAS_GIANT) &&
        Enum.any?(mounts, fn mount -> mount in ~w(MOUNT_GAS_SIPHON_I MOUNT_GAS_SIPHON_II MOUNT_GAS_SIPHON_III) end) &&
        ship["cargo"]["units"] < ship["cargo"]["capacity"] - 3 ->

        ShipTask.new(:siphon_resources, %{
          waypoint_symbol: ship["nav"]["waypointSymbol"]
        })
      true ->
        ShipTask.new(:idle)
    end
  end

  def hauling_ship(game, ship_symbol) do
    ShipAutomaton.new(game, ship_symbol, &hauling_phase/2)
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

  def surveyor_ship(game, ship_symbol) do
    ShipAutomaton.new(game, ship_symbol, &surveyor_phase/2)
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
    ShipAutomaton.new(game, ship_symbol, &trading_phase/2)
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
              if cargo_space > 0 do
                units_to_take = min(cargo_space, ship_units)
                remaining_cargo_space = cargo_space - units_to_take

                {:cont, {remaining_cargo_space, Map.put(pickups, ship_symbol, units_to_take)}}
              else
                {:halt, {cargo_space, pickups}}
              end
            end)

          units = Enum.map(ship_pickups, fn {_symbol, units} -> units end) |> Enum.sum()
          total_profit = price * units

          unless available_capacity >= units do
            raise "Made a task for more units than we have capacity for.... oops"
          end

          args =
            Map.merge(pickup_task.args, %{
              units: units,
              ship_pickups: ship_pickups,
              price: price,
              end_wp: market["symbol"],
              total_profit: total_profit
            })

          %{pickup_task | args: args}
        end)
      end)
      |> Enum.reject(fn pickup_task ->
        pickup_task.args.units == 0
      end)

      # Multiply each task by the different flight modes the ship can take to the pickup site.
      # adding fuel & time costs, and updating total profit accordingly to the task args.

      |> Enum.flat_map(fn pickup_task ->
        proximity = Game.distance_between(game, ship["nav"]["waypointSymbol"], pickup_task.args.start_wp)

        if ship["nav"]["waypointSymbol"] == pickup_task.args.start_wp do
          args =
            Map.merge(pickup_task.args, %{
              time_required: 0.5,
              start_flight_mode: "CRUISE",
              fuel_consumed: 0
            })

          [%{pickup_task | args: args}]
        else
          Ship.possible_travel_modes(ship, proximity)
          |> Enum.map(fn start_flight_mode ->

            start_fuel_consumption = Ship.fuel_cost(proximity) |> Map.fetch!(start_flight_mode)
            start_leg_time = Ship.travel_time(ship, proximity) |> Map.fetch!(start_flight_mode)

            fuel_cost = @average_fuel_price * start_fuel_consumption
            time_required = start_leg_time
            total_profit = pickup_task.args.total_profit - fuel_cost

            args =
              Map.merge(pickup_task.args, %{
                fuel_consumed: start_fuel_consumption,
                start_flight_mode: start_flight_mode,
                time_required: time_required,
                total_profit: total_profit,
              })

            %{pickup_task | args: args}
          end)
        end
      end)

      # Multiply each task by the different flight modes the ship can take to the selling site,
      # adding fuel & time costs, and updating total profit accordingly to the task args.

      # |> Enum.flat_map(fn pickup_task ->
      #   distance = Game.distance_between(game, pickup_task.args.start_wp, pickup_task.args.end_wp)
      #
      #   Ship.possible_travel_modes(ship, distance)
      #   |> Enum.map(fn transport_flight_mode ->
      #
      #     transport_fuel_consumption = Ship.fuel_cost(distance) |> Map.fetch!(transport_flight_mode)
      #     transport_leg_time = Ship.travel_time(ship, distance) |> Map.fetch!(transport_flight_mode)
      #
      #     fuel_cost = @average_fuel_price * transport_fuel_consumption
      #     time_required = pickup_task.args.time_required + transport_leg_time
      #     total_profit = pickup_task.args.total_profit - fuel_cost
      #
      #     args =
      #       Map.merge(pickup_task.args, %{
      #         transport_flight_mode: transport_flight_mode,
      #         time_required: time_required,
      #         total_profit: total_profit,
      #       })
      #
      #     %{pickup_task | args: args}
      #   end)
      # end)

      # Calculate profit over time for every task, adding it to the task args.

      |> Enum.map(fn pickup_task ->
          avg_price = Game.average_purchase_price(game, ship["nav"]["systemSymbol"], pickup_task.args.trade_symbol)

          args =
            Map.merge(pickup_task.args, %{
              profit_over_time: pickup_task.args.total_profit / pickup_task.args.time_required,
              expense: avg_price * pickup_task.args.units
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

            avg_price = Game.average_selling_price(game, ship["nav"]["systemSymbol"], item["symbol"])

            ShipTask.new(
              :selling,
              %{
                fuel_consumed: fuel_used,
                waypoint_symbol: market["symbol"],
                trade_symbol: item["symbol"],
                price: price,
                units: units,
                total_profit: total_profit,
                flight_mode: flight_mode,
                profit_over_time: profit_over_time,
                expense: avg_price * units
              }
            )
          end)
        end)
      end)

    trade_tasks =
      Game.trading_pairs(game, ship["nav"]["systemSymbol"])
      |> Enum.map(fn trade_task ->
        cargo_space = ship["cargo"]["capacity"] - ship["cargo"]["units"]

        units =
          (max(game.agent["credits"] - 5_000, 0) / trade_task.args.credits_required)
          |> min(cargo_space)
          |> min(trade_task.args.volume)
          |> trunc()

        total_profit = units * trade_task.args.profit

        args =
          Map.merge(trade_task.args, %{
            units: units,
            total_profit: total_profit,
            expense: units * trade_task.args.credits_required
          })

        %{trade_task | args: args}
      end)
      |> Enum.flat_map(fn trade_task ->
        proximity = Game.distance_between(game, ship["nav"]["waypointSymbol"], trade_task.args.start_wp)

        Ship.possible_travel_modes(ship, proximity)
        |> Enum.map(fn start_flight_mode ->
            start_fuel_consumption = Ship.fuel_cost(proximity) |> Map.fetch!(start_flight_mode)
            start_leg_time = Ship.travel_time(ship, proximity) |> Map.fetch!(start_flight_mode)

            fuel_cost = @average_fuel_price * start_fuel_consumption
            time_required = start_leg_time

            args =
              Map.merge(trade_task.args, %{
                start_fuel_consumed: start_fuel_consumption,
                fuel_consumed: start_fuel_consumption,
                total_profit: trade_task.args.total_profit - fuel_cost,
                start_flight_mode: start_flight_mode,
                time_required: time_required
              })

            %{trade_task | args: args}
          end)
      end)
      |> Enum.flat_map(fn trade_task ->
        distance = Game.distance_between(game, trade_task.args.start_wp, trade_task.args.end_wp)

        Ship.possible_travel_modes(ship, distance)
        |> Enum.map(fn end_flight_mode ->
          end_fuel_consumption = Ship.fuel_cost(distance) |> Map.fetch!(end_flight_mode)
          end_leg_time = Ship.travel_time(ship, distance) |> Map.fetch!(end_flight_mode)

          fuel_cost = @average_fuel_price * end_fuel_consumption

          args =
            Map.merge(trade_task.args, %{
              end_fuel_consumed: end_fuel_consumption,
              fuel_consumed: trade_task.args.fuel_consumed + end_fuel_consumption,
              total_profit: trade_task.args.total_profit - fuel_cost,
              end_flight_mode: end_flight_mode,
              time_required: trade_task.args.time_required + end_leg_time
            })

          %{trade_task | args: args}
        end)
      end)
      |> Enum.reject(fn task -> task.args.units == 0 end)
      |> Enum.map(fn task ->
          args =
            Map.merge(task.args, %{
              profit_over_time: task.args.total_profit / task.args.time_required
            })

          %{task | args: args}
      end)

    best_task_score =
      (sell_tasks ++ trade_tasks ++ mining_pickup_tasks)
      |> tap(fn tasks ->
        Logger.debug("Ship #{ship_symbol} has #{Enum.count(tasks)} tasks to choose from.")
      end)
      |> Enum.map(fn task ->
        {task, Utility.score(game, ship_symbol, task)}
      end)
      |> Enum.reject(fn {_task, score} -> score < 0.01 end)
      |> Enum.sort_by(&elem(&1, 1), :desc)
      |> Enum.max_by(fn {_task, score} -> score end, fn -> nil end)

    if best_task_score do
      {best_task, utility_score} = best_task_score
      Logger.debug("Ship #{ship_symbol} chose task #{inspect best_task.name} with score #{utility_score} and this defintion:\n#{inspect best_task, pretty: true}")
      best_task
    end
  end
end
