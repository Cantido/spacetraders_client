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
    else
      new()
    end
  end

  def score(game, _ship_symbol, %ShipTask{name: :mine} = task) do
    avg_value = Game.average_extraction_value(game, task.args.waypoint_symbol)

    if avg_value == 0 do
      new()
      |> DecisionFactors.time(task.args.time_required)
      |> DecisionFactors.fuel_consumed(task.args.fuel_consumed)
      |> DecisionFactors.profit(100)
    else
      new()
      |> DecisionFactors.time(task.args.time_required)
      |> DecisionFactors.fuel_consumed(task.args.fuel_consumed)
      |> DecisionFactors.profit(avg_value)
    end
  end

  def score(_game, _ship_symbol, %ShipTask{name: :siphon_resources}) do
    # avg_value = Game.average_extraction_value(game, task.args.waypoint_symbol)
    #
    # if avg_value == 0 do
    #   new()
    #   |> DecisionFactors.distance(task.args.distance)
    # else
    #   new()
    #   |> DecisionFactors.distance(task.args.distance)
    #   |> DecisionFactors.income_over_time(avg_value / 60)
    # end
    new()
  end

  def score(_, _, _) do
    new()
  end
end
