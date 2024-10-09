defmodule SpacetradersClient.DecisionFactors do
  alias SpacetradersClient.Utility
  alias SpacetradersClient.Curves

  def income_over_time(factors, x) do
    y = Curves.quadratic(x, 5_000, 0.333)

    put_factor(factors, %{name: :income_over_time, input: x, output: y})
  end

  def fuel_consumed(factors, x) do
    y = 1 - Curves.smoothstep(x, 0, 1_000)

    put_factor(factors, %{name: :fuel_consumed, input: x, output: y, weight: 0.1})
  end

  def time(factors, x) do
    y = Curves.quadratic(x, 60 * 60, 0.333)
      |> Curves.invert()

    put_factor(factors, %{name: :time, input: x, output: y})
  end

  def distance(factors, x) do
    y =
      Curves.linear(x, 1_000)
      |> Curves.invert()

    put_factor(factors, %{name: :distance, input: x, output: y})
  end

  def bank(factors, x) do
    y = Curves.quadratic(x, 1_000_000, 0.333)

    put_factor(factors, %{name: :bank, input: x, output: y})
  end

  def profit(factors, x) do
    y = Curves.quadratic(x, 10_000, 0.333)

    put_factor(factors, %{name: :profit, input: x, output: y, weight: 2})
  end

  def roi(factors, x) do
    y = Curves.smoothstep(x, 1, 2)

    put_factor(factors, %{name: :roi, input: x, output: y})
  end

  defp put_factor(%Utility{} = util, factor) do
    %{util | factors: [factor | util.factors]}
  end
end
