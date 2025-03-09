defmodule SpacetradersClient.Utility do
  alias SpacetradersClient.Game
  alias SpacetradersClient.DecisionFactors
  alias SpacetradersClient.ShipTask

  @derive Jason.Encoder
  defstruct [
    factors: []
  ]

  def new, do: %__MODULE__{}

  def score(%__MODULE__{} = util) do
    {sum, weight} =
      get_in(util, [Access.key(:factors), Access.all()])
      |> Enum.reduce({0, 0}, fn df, {sum, weight} ->
        df_weight = Map.get(df, :weight, 1)
        {sum + df.output * df_weight, weight + df_weight}
      end)

    if weight == 0 do
      0.0
    else
      sum / weight
    end
  end

  def score(_game, _ship_symbol, %ShipTask{name: :buying} = task) do
    if task.args.total_profit > 0 do
      new()
      |> DecisionFactors.profit(task.args.total_profit)
      |> DecisionFactors.fuel_consumed(task.args.fuel_consumed)
    else
      new()
    end
  end

  def score(_game, _ship_symbol, %ShipTask{name: :selling} = task) do
    if task.args.total_profit > 0 do
      new()
      |> DecisionFactors.profit(task.args.total_profit)
      |> DecisionFactors.fuel_consumed(task.args.fuel_consumed)
      |> DecisionFactors.time(task.args.time_required)
    else
      new()
    end
  end

  def score(_game, _ship_symbol, %ShipTask{name: :deliver_construction_materials} = task) do
    new()
    |> DecisionFactors.time(task.args.time_required)
    |> DecisionFactors.construction_supply(task.args.units)
  end

  def score(_game, _ship_symbol, %ShipTask{name: :trade} = task) do
    if task.args.total_profit > 0 do
      new()
      |> DecisionFactors.profit(task.args.total_profit)
      |> DecisionFactors.fuel_consumed(task.args.fuel_consumed)
      |> DecisionFactors.time(task.args.time_required)
    else
      new()
    end
  end

  def score(_game, _ship_symbol, %ShipTask{name: :pickup} = task) do
    if task.args.total_profit > 0 do
      new()
      |> DecisionFactors.profit(task.args.total_profit)
      |> DecisionFactors.fuel_consumed(task.args.fuel_consumed)
      |> DecisionFactors.time(task.args.time_required)
      |> DecisionFactors.cooperation_bonus()
    else
      new()
    end
  end

  def score(game, ship_symbol, %ShipTask{name: :mine} = task) do
    ship = Game.ship(game, ship_symbol)

    avg_value = Game.average_extraction_value(game, task.args.waypoint_symbol)

    if avg_value == 0 do
      new()
      |> DecisionFactors.profit(100)
    else
      new()
      |> DecisionFactors.profit(avg_value)
    end
    |> DecisionFactors.time(task.args.time_required)
    |> DecisionFactors.fuel_consumed(task.args.fuel_consumed)
    |> then(fn df ->
      if ship["registration"]["role"] == "EXCAVATOR" do
        DecisionFactors.role_bonus(df)
      else
        df
      end
    end)
  end

  def score(_game, _ship_symbol, %ShipTask{name: :goto} = task) do
    new()
    |> DecisionFactors.market_visibility_bonus()
    |> DecisionFactors.time(task.args.time_required)
  end

  def score(game, ship_symbol, %ShipTask{name: :siphon_resources} = task) do
    ship = Game.ship(game, ship_symbol)

    avg_value = Game.average_extraction_value(game, task.args.waypoint_symbol)

    if avg_value == 0 do
      new()
      |> DecisionFactors.profit(1000)
    else
      new()
      |> DecisionFactors.profit(avg_value)
    end
    |> DecisionFactors.time(task.args.time_required)
    |> DecisionFactors.fuel_consumed(task.args.fuel_consumed)
    |> then(fn df ->
      if ship["registration"]["role"] == "EXCAVATOR" do
        DecisionFactors.role_bonus(df)
      else
        df
      end
    end)
  end

  def score(_, _, _) do
    new()
  end
end
