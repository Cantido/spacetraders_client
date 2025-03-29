defprotocol SpacetradersClient.Action do
  def customize(action, ship)
  def variations(action, ship)
  def decision_factors(action, ship)
end
