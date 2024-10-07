defmodule SpacetradersClient.ShipAutomaton do
  alias SpacetradersClient.Ship
  alias SpacetradersClient.ShipTask
  alias SpacetradersClient.Utility
  alias SpacetradersClient.Behaviors
  alias SpacetradersClient.Game
  require Logger

  @enforce_keys [
    :ship_symbol,
    :task_fun
  ]
  defstruct [
    :ship_symbol,
    :tree,
    :current_action,
    :task_fun
  ]

  @average_fuel_price 2 # per fuel unit, not market unit!!

  def new(ship_symbol, task_fun) when is_binary(ship_symbol) and is_function(task_fun, 2) do
    %__MODULE__{
      ship_symbol: ship_symbol,
      task_fun: task_fun
    }
  end

  def tick(%__MODULE__{} = struct, %Game{} = game) do
    struct =
      if struct.tree do
        struct
      else
        game_actions =
          Game.actions(game)

        more_ship_actions = ship_actions(struct, game)
        ship_actions = struct.task_fun.(game, struct.ship_symbol)

        actions =
          (game_actions ++ ship_actions ++ more_ship_actions)
          |> Enum.map(&customize_action(struct, game, &1))
          |> Enum.flat_map(&action_variations(struct, game, &1))
          |> Enum.map(&estimate_costs(struct, game, &1))

        task = select_action(struct, game, actions)

        tree = Behaviors.for_task(task)

        %{struct | current_action: task, tree: tree}
      end

    {result, tree, %{game: game}} = Taido.BehaviorTree.tick(struct.tree, %{ship_symbol: struct.ship_symbol, game: game})

    Logger.debug("Automaton for #{struct.ship_symbol} returned #{result} for task #{struct.current_action.name}")

    case result do
      :running ->
        {%{struct | tree: tree}, game}

      _ ->
        if struct.tree do
          _ = Taido.BehaviorTree.terminate(struct.tree)
        end

        {%{struct | tree: nil, current_action: nil}, game}
    end
  end

  defp customize_action(struct, game, %ShipTask{name: :trade} = trade_task) do
    ship = Game.ship(game, struct.ship_symbol)

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

    %ShipTask{trade_task | args: args}
  end

  defp customize_action(struct, game, %ShipTask{name: :pickup} = pickup_task) do
    ship = Game.ship(game, struct.ship_symbol)

    available_capacity =
      (ship["cargo"]["capacity"] - ship["cargo"]["units"])
      |> min(pickup_task.args.volume)

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
    total_profit = pickup_task.args.price * units

    unless available_capacity >= units do
      raise "Made a task for more units than we have capacity for.... oops"
    end

    args =
      Map.merge(pickup_task.args, %{
        units: units,
        ship_pickups: ship_pickups,
        total_profit: total_profit
      })

    %ShipTask{pickup_task | args: args}
  end


  defp customize_action(_struct, _game, action) do
    action
  end

  defp action_variations(struct, game, %ShipTask{name: :pickup} = pickup_task) do
    ship = Game.ship(game, struct.ship_symbol)

    proximity = Game.distance_between(game, ship["nav"]["waypointSymbol"], pickup_task.args.start_wp)

    if ship["nav"]["waypointSymbol"] == pickup_task.args.start_wp do
      args =
        Map.merge(pickup_task.args, %{
          time_required: 0.5,
          start_flight_mode: "CRUISE",
          fuel_consumed: 0
        })

      [%ShipTask{pickup_task | args: args}]
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

        %ShipTask{pickup_task | args: args}
      end)
    end
  end

  defp action_variations(struct, game, %ShipTask{name: :trade} = trade_task) do
    ship = Game.ship(game, struct.ship_symbol)

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

        %ShipTask{trade_task | args: args}
      end)
    end)
  end

  defp action_variations(_struct, _game, action) do
    [action]
  end

  defp estimate_costs(struct, game, %ShipTask{name: :pickup} = pickup_task) do
    ship = Game.ship(game, struct.ship_symbol)

    avg_price = Game.average_purchase_price(game, ship["nav"]["systemSymbol"], pickup_task.args.trade_symbol)

    args =
      Map.merge(pickup_task.args, %{
        profit_over_time: pickup_task.args.total_profit / pickup_task.args.time_required,
        expense: avg_price * pickup_task.args.units
      })

    %ShipTask{pickup_task | args: args}
  end

  defp estimate_costs(_struct, _game, %ShipTask{name: :trade} = task) do
    args =
      Map.merge(task.args, %{
        profit_over_time: task.args.total_profit / task.args.time_required
      })

    %{task | args: args}
  end

  defp estimate_costs(_struct, _game, action) do
    action
  end

  defp select_action(%__MODULE__{} = struct, %Game{} = game, actions) when is_list(actions) do
    Logger.debug("Ship #{struct.ship_symbol} has #{Enum.count(actions)} tasks to choose from.")

    ship = Game.ship(game, struct.ship_symbol)

    best_task_score =
      actions
      |> Enum.filter(fn %ShipTask{} = task ->
        ShipTask.meets_conditions?(task, ship)
      end)
      |> Enum.map(fn task ->
        {task, Utility.score(game, struct.ship_symbol, task)}
      end)
      |> Enum.reject(fn {_task, score} -> score < 0.01 end)
      |> Enum.sort_by(&elem(&1, 1), :desc)
      |> Enum.max_by(fn {_task, score} -> score end, fn -> nil end)

    if best_task_score do
      {best_task, utility_score} = best_task_score
      Logger.debug("Ship #{struct.ship_symbol} chose task #{inspect best_task.name} with score #{utility_score} and this defintion:\n#{inspect best_task, pretty: true}")
      best_task
    else
      ShipTask.new(:idle)
    end
  end

  defp ship_actions(%__MODULE__{} = struct, %Game{} = game) do
    ship = Game.ship(game, struct.ship_symbol)

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
  end

  def handle_message(%__MODULE__{} = struct, msg) do
    if struct.tree do
      new_tree = Taido.BehaviorTree.handle_message(struct.tree, msg)

      %{struct | tree: new_tree}
    else
      struct
    end
  end
end
