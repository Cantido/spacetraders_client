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
    alias SpacetradersClient.Game.Agent
    alias SpacetradersClient.Game.Ship
    alias SpacetradersClient.Game
    alias SpacetradersClient.Actions.TradeGoods
    alias SpacetradersClient.Repo

    # per fuel unit, not market unit!!
    @average_fuel_price 2

    def customize(%TradeGoods{} = action, ship) do
      cargo_space = ship.cargo_capacity - Ship.cargo_current(ship)
      agent = Repo.get(Agent, ship.agent_symbol)

      units =
        (max(agent.credits - 5_000, 0) / action.buy_price)
        |> min(cargo_space)
        |> min(action.market_volume)
        |> trunc()

      %{action | units: units}
    end

    def variations(%TradeGoods{} = action, _ship) do
      ~w(cruise drift)a
      |> Enum.flat_map(fn start_flight_mode ->
        ~w(cruise drift)a
        |> Enum.map(fn end_flight_mode ->
          %{action | start_flight_mode: start_flight_mode, end_flight_mode: end_flight_mode}
        end)
      end)
    end

    def decision_factors(%TradeGoods{} = action, %Ship{} = ship) do
      distance_to_start =
        Game.distance_between(ship.nav_waypoint_symbol, action.buy_waypoint_symbol)

      start_fuel_consumption =
        Ship.fuel_cost(distance_to_start) |> Map.fetch!(action.start_flight_mode)

      start_fuel_cost = @average_fuel_price * start_fuel_consumption

      start_leg_time =
        Ship.travel_time(ship, distance_to_start) |> Map.fetch!(action.start_flight_mode)

      distance_to_end =
        Game.distance_between(action.buy_waypoint_symbol, action.sell_waypoint_symbol)

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
