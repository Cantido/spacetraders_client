defmodule SpacetradersClient.Utility do
  alias SpacetradersClient.DecisionFactors
  alias SpacetradersClient.ShipTask

  def score(_game, _ship_symbol, %ShipTask{name: :buying} = task) do
    profit_over_time_factor =
      task.args.profit_over_time
      |> DecisionFactors.income_over_time()

    fuel_consumption_factor =
      task.args.fuel_consumed
      |> DecisionFactors.fuel_consumed()

    avg([
      profit_over_time_factor,
      fuel_consumption_factor
    ])
  end

  def score(_game, _ship_symbol, %ShipTask{name: :selling} = task) do
    profit_over_time_factor =
      task.args.profit_over_time
      |> DecisionFactors.income_over_time()

    fuel_consumption_factor =
      task.args.fuel_consumed
      |> DecisionFactors.fuel_consumed()

    avg([
      profit_over_time_factor,
      fuel_consumption_factor
    ])
  end

  def score(_game, _ship_symbol, %ShipTask{name: :trade} = task) do
    profit_over_time_factor =
      task.args.profit_over_time
      |> DecisionFactors.income_over_time()

    fuel_consumption_factor =
      task.args.fuel_consumed
      |> DecisionFactors.fuel_consumed()

    avg([
      profit_over_time_factor,
      fuel_consumption_factor
    ])
  end

  def score(_game, _ship_symbol, %ShipTask{name: :pickup} = task) do
    profit_over_time_factor =
      task.args.profit_over_time
      |> DecisionFactors.income_over_time()

    fuel_consumption_factor =
      task.args.fuel_consumed
      |> DecisionFactors.fuel_consumed()

    avg([
      profit_over_time_factor,
      fuel_consumption_factor
    ])
  end

  def score(_, _, _) do
    0.0
  end

  defp avg(list) do
    Enum.sum(list) / Enum.count(list)
  end
end
