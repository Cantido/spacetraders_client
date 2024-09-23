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

  def dock_ship(client, ship_symbol) do
    Tesla.post(client, "/v2/my/ships/#{ship_symbol}/dock", "")
  end

  def orbit_ship(client, ship_symbol) do
    Tesla.post(client, "/v2/my/ships/#{ship_symbol}/orbit", "")
  end
  def refuel_ship(client, ship_symbol) do
    Tesla.post(client, "/v2/my/ships/#{ship_symbol}/refuel", "")
  end
end
