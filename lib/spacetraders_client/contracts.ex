defmodule SpacetradersClient.Contracts do
  def my_contracts(client) do
    Tesla.get(client, "/v2/my/contracts")
  end

  def get_contract(client, id) do
    Tesla.get(client, "/v2/my/contracts/#{id}")
  end

  def deliver_cargo(client, id, ship_symbol, trade_symbol, quantity) do
    Tesla.post(client, "/v2/my/contracts/#{id}/deliver", %{
      shipSymbol: ship_symbol,
      tradeSymbol: trade_symbol,
      units: quantity
    })
  end
end
