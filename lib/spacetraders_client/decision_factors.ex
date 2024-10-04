defmodule SpacetradersClient.DecisionFactors do
  alias SpacetradersClient.Curves

  def income_over_time(i) do
    Curves.quadratic(i, 10_000, 0.333)
  end

  def time(s) do
    Curves.smoothstep(s, 15 * 60, 0)
  end

  def distance(d) do
    Curves.quadratic(d, 1_000, 5)
    |> Curves.invert()
  end

  def bank(available_credits) do
    Curves.quadratic(available_credits, 1_000_000, 0.333)
  end

  def profit(credits) do
    Curves.quadratic(credits, 10_000, 0.333)
  end

  def roi(ratio) do
    Curves.smoothstep(ratio, 1, 2)
  end

end
