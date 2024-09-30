defmodule SpacetradersClient.Ship do
  def has_saleable_cargo?(ship, market) do
    Enum.any?(ship["cargo"]["inventory"], fn cargo_item ->
      trade_good = Enum.find(market["tradeGoods"], fn t -> t["symbol"] == cargo_item["symbol"] end)

      trade_good && trade_good["sellPrice"] > 0
    end)
  end

  def cargo_to_sell(ship, market) do
    Enum.reject(ship["cargo"]["inventory"], fn cargo_item ->
      trade_good = Enum.find(market["tradeGoods"], fn t -> t["symbol"] == cargo_item["symbol"] end)

      trade_good && trade_good["sellPrice"] > 0
    end)
  end

  def cargo_to_jettison(ship, market) do
    Enum.reject(ship["cargo"]["inventory"], fn cargo_item ->
      trade_good = Enum.find(market["tradeGoods"], fn t -> t["symbol"] == cargo_item["symbol"] end)

      trade_good && trade_good["sellPrice"] > 0
    end)
  end
end
