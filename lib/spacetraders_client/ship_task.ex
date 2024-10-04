defmodule SpacetradersClient.ShipTask do
  alias SpacetradersClient.Ship
  alias SpacetradersClient.Game
  defstruct [
    :name,
    args: %{},
    conditions: []
  ]

  @cost_per_second 5

  def new(name, args \\ %{}, conditions \\ []) do
    %__MODULE__{
      name: name,
      args: args,
      conditions: conditions
    }
  end

  def meets_conditions?(task, agent) do
    Enum.all?(task.conditions, fn condition ->
      condition.(agent)
    end)
  end

  def cost(%{name: :goto} = action, game, ship_symbol) do
    ship = Game.ship(game, ship_symbol)
    distance = Game.distance_between(game, ship["nav"]["waypointSymbol"], action.args.waypoint_symbol)
    time = Ship.travel_time(ship, distance)

    @cost_per_second * time["CRUISE"]
  end

  def cost(%{name: :sell_to_market} = action, game, ship_symbol) do
    ship = Game.ship(game, ship_symbol)

    units_available = Enum.find(ship["cargo"]["inventory"], fn inv ->
      inv["symbol"] == action.args.trade_symbol
    end)
    |> Map.get("units", 0)

    amount_to_sell =
      min(units_available, action.args.volume)

    profit = amount_to_sell * action.args.price

    distance = Game.distance_between(game, ship["nav"]["waypointSymbol"], action.args.waypoint_symbol)
    time = Ship.travel_time(ship, distance)

    (@cost_per_second * time["CRUISE"]) - profit
  end

  def cost(%{name: :purchase_from_market} = action, game, ship_symbol) do
    ship = Game.ship(game, ship_symbol)

    cargo_space = ship["cargo"]["capacity"] - ship["cargo"]["units"]

    amount_to_buy =
      (max(game.agent["credits"] - 5_000, 0) / action.args.price)
      |> min(cargo_space)
      |> min(action.args.volume)
      |> trunc()

    amount_to_buy * action.args.price
  end

  def cost(%{name: :refuel} = action, game, ship_symbol) do
    ship = Game.ship(game, ship_symbol)

    amount = Float.ceil(ship["fuel"]["capacity"] - ship["fuel"]["current"] / 100)

    amount * action.args.price
  end

  def cost(%{name: :idle}, _game, _ship_symbol) do
    0.0
  end
end
