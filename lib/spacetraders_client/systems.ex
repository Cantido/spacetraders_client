defmodule SpacetradersClient.Systems do
  def get_system(client, system_symbol) do
    Tesla.get(client, "/v2/systems/#{system_symbol}")
  end

  def get_waypoint(client, system_symbol, waypoint_symbol) do
    Tesla.get(client, "/v2/systems/#{system_symbol}/waypoints/#{waypoint_symbol}")
  end

  def get_market(client, system_symbol, waypoint_symbol) do
    Tesla.get(client, "/v2/systems/#{system_symbol}/waypoints/#{waypoint_symbol}/market")
  end
end
