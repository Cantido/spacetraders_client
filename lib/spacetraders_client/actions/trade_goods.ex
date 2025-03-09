defmodule SpacetradersClient.Actions.TradeGoods do
  defstruct [
    :buy_waypoint_symbol,
    :buy_price,
    :sell_waypoint_symbol,
    :sell_price,
    :market_volume,
    :trade_symbol,
    :units,
    :start_flight_mode,
    :end_flight_mode
  ]


  defimpl SpacetradersClient.Action do
    alias SpacetradersClient.Ship
    alias SpacetradersClient.Game
    alias SpacetradersClient.Actions.TradeGoods

    @average_fuel_price 2 # per fuel unit, not market unit!!

    def customize(%TradeGoods{} = action, game, ship_symbol) do
      ship = Game.ship(game, ship_symbol)

      cargo_space = ship["cargo"]["capacity"] - ship["cargo"]["units"]

      units =
        (max(game.agent["credits"] - 5_000, 0) / action.buy_price)
        |> min(cargo_space)
        |> min(action.market_volume)
        |> trunc()

      %{action | units: units}
    end

    def variations(%TradeGoods{} = action, _game, _ship_symbol) do
      ~w(CRUISE DRIFT)
      |> Enum.flat_map(fn start_flight_mode ->
        ~w(CRUISE DRIFT)
        |> Enum.map(fn end_flight_mode ->
          %{action | start_flight_mode: start_flight_mode, end_flight_mode: end_flight_mode}
        end)
      end)
    end


    def decision_factors(%TradeGoods{} = action, game, ship_symbol) do
      ship = Game.ship(game, ship_symbol)

      distance_to_start = Game.distance_between(game, ship["nav"]["waypointSymbol"], action.buy_waypoint_symbol)

      start_fuel_consumption = Ship.fuel_cost(distance_to_start) |> Map.fetch!(action.start_flight_mode)
      start_fuel_cost = @average_fuel_price * start_fuel_consumption
      start_leg_time = Ship.travel_time(ship, distance_to_start) |> Map.fetch!(action.start_flight_mode)

      distance_to_end  = Game.distance_between(game, action.buy_waypoint_symbol, action.sell_waypoint_symbol)

      end_fuel_consumption = Ship.fuel_cost(distance_to_end) |> Map.fetch!(action.end_flight_mode)
      end_fuel_cost = @average_fuel_price * end_fuel_consumption
      end_leg_time = Ship.travel_time(ship, distance_to_end) |> Map.fetch!(action.end_flight_mode)

      gross_profit = (action.sell_price - action.buy_price) * action.units

      %{
        time: start_leg_time + end_leg_time,
        fuel_consumed: start_fuel_consumption + end_fuel_consumption,
        profit: gross_profit - start_fuel_cost - end_fuel_cost
      }
    end
  end
end
