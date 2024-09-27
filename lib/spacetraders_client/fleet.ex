defmodule SpacetradersClient.Fleet do
  def list_ships(client) do
    Tesla.get(client, "/v2/my/ships")
  end

  def get_ship(client, ship_symbol) do
    Tesla.get(client, "/v2/my/ships/#{ship_symbol}")
  end

  def get_ship_cargo(client, ship_symbol) do
    Tesla.get(client, "/v2/my/ships/#{ship_symbol}/cargo")
  end

  def purchase_ship(client, waypoint_symbol, ship_type) do
    Tesla.post(client, "/v2/my/ships", %{shipType: ship_type, waypointSymbol: waypoint_symbol})
  end

  def sell_cargo(client, ship_symbol, trade_symbol, units) do
    Tesla.post(client, "/v2/my/ships/#{ship_symbol}/sell", %{symbol: trade_symbol, units: units})
  end

  def dock_ship(client, ship_symbol) do
    Tesla.post(client, "/v2/my/ships/#{ship_symbol}/dock", "")
  end

  def orbit_ship(client, ship_symbol) do
    Tesla.post(client, "/v2/my/ships/#{ship_symbol}/orbit", "")
  end

  def refuel_ship(client, ship_symbol) do
    Tesla.post(client, "/v2/my/ships/#{ship_symbol}/refuel", "")
  end

  def navigate_ship(client, ship_symbol, waypoint_symbol) do
    Tesla.post(client, "/v2/my/ships/#{ship_symbol}/navigate", %{waypointSymbol: waypoint_symbol})
  end

  def set_flight_mode(client, ship_symbol, flight_mode) do
    Tesla.patch(client, "/v2/my/ships/#{ship_symbol}/nav", %{flightMode: flight_mode})
  end

  def create_survey(client, ship_symbol) do
    Tesla.post(client, "/v2/my/ships/#{ship_symbol}/survey", "")
  end

  def extract_resources(client, ship_symbol) do
    Tesla.post(client, "/v2/my/ships/#{ship_symbol}/extract", "")
  end

  def extract_resources(client, ship_symbol, survey) do
    Tesla.post(client, "/v2/my/ships/#{ship_symbol}/extract/survey", survey)
  end

  def jettison_cargo(client, ship_symbol, item_symbol, units) do
    Tesla.post(client, "/v2/my/ships/#{ship_symbol}/jettison", %{symbol: item_symbol, units: units})
  end
end
