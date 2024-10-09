defmodule SpacetradersClient.ShipAutomaton do
  alias SpacetradersClient.Ship
  alias SpacetradersClient.ShipTask
  alias SpacetradersClient.Utility
  alias SpacetradersClient.Behaviors
  alias SpacetradersClient.Game

  @enforce_keys [
    :ship_symbol
  ]
  defstruct [
    :ship_symbol,
    :tree,
    :current_action,
    alternative_actions: [],
    action_history: []
  ]

  @average_fuel_price 2 # per fuel unit, not market unit!!
  @mining_cooldown 70

  def new(ship_symbol) when is_binary(ship_symbol) do
    %__MODULE__{
      ship_symbol: ship_symbol
    }
  end

  def tick(%__MODULE__{} = struct, %Game{} = game) do
    struct =
      if struct.tree do
        struct
      else
        ship = Game.ship(game, struct.ship_symbol)

        game_actions =
          Game.actions(game)

        ship_actions = ship_actions(struct, game)

        actions =
          (game_actions ++ ship_actions)
          |> Enum.map(&customize_action(struct, game, &1))
          |> Enum.flat_map(&action_variations(struct, game, &1))
          |> Enum.map(&estimate_costs(struct, game, &1))
          |> Enum.filter(&ShipTask.meets_conditions?(&1, ship))

        struct = select_action(struct, game, actions)

        tree = Behaviors.for_task(struct.current_action)

        %{struct | tree: tree}
      end

    {result, tree, %{game: game}} = Taido.BehaviorTree.tick(struct.tree, %{ship_symbol: struct.ship_symbol, game: game})

    case result do
      :running ->
        {%{struct | tree: tree}, game}

      _ ->
        if struct.tree do
          _ = Taido.BehaviorTree.terminate(struct.tree)
        end

        struct =
          struct
          |> Map.update!(:action_history, fn history ->
            Enum.take([struct.current_action | history], 10)
          end)
          |> Map.put(:tree, nil)
          |> Map.put(:current_action, nil)

        {struct, game}
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

    ShipTask.assign(trade_task, %{
      units: units,
      total_profit: total_profit,
      expense: units * trade_task.args.credits_required
    })
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

    ShipTask.assign(pickup_task, %{
      units: units,
      ship_pickups: ship_pickups,
      total_profit: total_profit
    })
  end

  defp customize_action(_struct, _game, action) do
    action
  end

  defp action_variations(struct, game, %ShipTask{name: :pickup} = pickup_task) do
    ship = Game.ship(game, struct.ship_symbol)

    proximity = Game.distance_between(game, ship["nav"]["waypointSymbol"], pickup_task.args.start_wp)

    if ship["nav"]["waypointSymbol"] == pickup_task.args.start_wp do
      args = %{
        time_required: 0.5,
        start_flight_mode: "CRUISE",
        fuel_consumed: 0,
        distance: proximity
      }

      [ShipTask.assign(pickup_task, args)]
    else
      Ship.possible_travel_modes(ship, proximity)
      |> Enum.map(fn start_flight_mode ->

        start_fuel_consumption = Ship.fuel_cost(proximity) |> Map.fetch!(start_flight_mode)
        start_leg_time = Ship.travel_time(ship, proximity) |> Map.fetch!(start_flight_mode)

        fuel_cost = @average_fuel_price * start_fuel_consumption
        time_required = start_leg_time
        total_profit = pickup_task.args.total_profit - fuel_cost

        pickup_task
        |> ShipTask.variation(%{
          fuel_consumed: start_fuel_consumption,
          start_flight_mode: start_flight_mode,
          time_required: time_required,
          total_profit: total_profit,
          distance: proximity
        })
        |> ShipTask.add_condition(fn ship -> start_fuel_consumption < ship["fuel"]["capacity"] end)
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

        ShipTask.variation(trade_task, %{
          start_fuel_consumed: start_fuel_consumption,
          fuel_consumed: start_fuel_consumption,
          total_profit: trade_task.args.total_profit - fuel_cost,
          start_flight_mode: start_flight_mode,
          time_required: time_required
        })
      end)
    |> Enum.flat_map(fn trade_task ->
      distance = Game.distance_between(game, trade_task.args.start_wp, trade_task.args.end_wp)

      Ship.possible_travel_modes(ship, distance)
      |> Enum.map(fn end_flight_mode ->
        end_fuel_consumption = Ship.fuel_cost(distance) |> Map.fetch!(end_flight_mode)
        end_leg_time = Ship.travel_time(ship, distance) |> Map.fetch!(end_flight_mode)

        fuel_cost = @average_fuel_price * end_fuel_consumption

        ShipTask.variation(trade_task, %{
          end_fuel_consumed: end_fuel_consumption,
          fuel_consumed: trade_task.args.fuel_consumed + end_fuel_consumption,
          total_profit: trade_task.args.total_profit - fuel_cost,
          end_flight_mode: end_flight_mode,
          time_required: trade_task.args.time_required + end_leg_time
        })
      end)
    end)
    |> Enum.map(fn task ->
      task
      |> ShipTask.add_condition(fn ship -> task.args.start_fuel_consumed < ship["fuel"]["capacity"] end)
      |> ShipTask.add_condition(fn ship -> task.args.end_fuel_consumed < ship["fuel"]["capacity"] end)
    end)
  end

  defp action_variations(_struct, _game, %ShipTask{name: :mine} = task) do
    ~w(CRUISE DRIFT)
    |> Enum.map(fn flight_mode ->
      ShipTask.variation(task, :flight_mode, flight_mode)
    end)
  end

  defp action_variations(_struct, _game, action) do
    [action]
  end

  defp estimate_costs(struct, game, %ShipTask{name: :pickup} = pickup_task) do
    ship = Game.ship(game, struct.ship_symbol)

    avg_price = Game.average_purchase_price(game, ship["nav"]["systemSymbol"], pickup_task.args.trade_symbol)

    pickup_task
    |> ShipTask.assign(:profit_over_time, pickup_task.args.total_profit / pickup_task.args.time_required)
    |> ShipTask.assign(:expense, avg_price * pickup_task.args.units)
  end

  defp estimate_costs(_struct, _game, %ShipTask{name: :trade} = task) do
    ShipTask.assign(task, :profit_over_time, task.args.total_profit / task.args.time_required)
  end

  defp estimate_costs(struct, game, %ShipTask{name: :mine} = task) do
    ship = Game.ship(game, struct.ship_symbol)

    distance = Game.distance_between(game, ship["nav"]["waypointSymbol"], task.args.waypoint_symbol)

    fuel_consumed = Ship.fuel_cost(distance) |> Map.fetch!(task.args.flight_mode)
    travel_time = Ship.travel_time(ship, distance) |> Map.fetch!(task.args.flight_mode)

    fuel_cost = @average_fuel_price * fuel_consumed

    task
    |> ShipTask.assign(%{
      distance: distance,
      fuel_consumed: fuel_consumed,
      fuel_cost: fuel_cost,
      time_required: travel_time + @mining_cooldown
    })
    |> ShipTask.add_condition(fn ship -> fuel_consumed < ship["fuel"]["capacity"] end)
  end

  defp estimate_costs(_struct, _game, action) do
    action
  end

  defp select_action(%__MODULE__{} = struct, %Game{} = game, actions) when is_list(actions) do
    best_actions =
      actions
      |> Enum.map(fn task ->
        task = ShipTask.put_utility(task, Utility.score(game, struct.ship_symbol, task))
        score = ShipTask.utility_score(task)

        {task, score}
      end)
      |> Enum.reject(fn {_task, score} -> score < 0.01 end)
      |> Enum.sort_by(&elem(&1, 1), :desc)
      |> Enum.take(10)

    {best_task, utility_score} =
      best_actions
      |> Enum.max_by(fn {_task, score} -> score end, fn -> {ShipTask.new(:idle), 0} end)

    %{struct | current_action: best_task, alternative_actions: Enum.map(best_actions, &elem(&1, 0))}
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
              time_required: travel_time,
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
