defprotocol SpacetradersClient.Action do
  def apply(action, game, ship_symbol)
  def cost(action, game, ship_symbol)
end
