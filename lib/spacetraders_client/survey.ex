defmodule SpacetradersClient.Survey do
  def profitability(survey, price_fun) do
    deposits =
      survey["deposits"]
      |> Enum.map(fn d -> d["symbol"] end)
      |> Enum.frequencies()

    weight_sum =
      Enum.map(deposits, fn {_d, freq} -> freq end)
      |> Enum.sum()

    Enum.map(deposits, fn {dep, freq} ->
      price_fun.(dep) * freq / weight_sum
    end)
    |> Enum.sum()
  end
end
