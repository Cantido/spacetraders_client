defprotocol SpacetradersClient.Action do
  def customize(action, game, ship_symbol)
  def variations(action, game, ship_symbol)
  def decision_factors(action, game, ship_symbol)
end
