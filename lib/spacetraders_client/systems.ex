defmodule SpacetradersClient.Systems do
  def get_system(client, system_symbol) do
    Tesla.get(client, "/v2/systems/#{system_symbol}")
  end

  def get_waypoint(client, system_symbol, waypoint_symbol) do
    Tesla.get(client, "/v2/systems/#{system_symbol}/waypoints/#{waypoint_symbol}")
  end

  def list_waypoints(client, system_symbol, opts \\ []) do
    limit = Keyword.get(opts, :limit, 20)
    page = Keyword.get(opts, :page, 1)
    Tesla.get(client, "/v2/systems/#{system_symbol}/waypoints?page=#{page}&limit=#{limit}")
  end

  def get_market(client, system_symbol, waypoint_symbol) do
    Tesla.get(client, "/v2/systems/#{system_symbol}/waypoints/#{waypoint_symbol}/market")
  end

  def get_shipyard(client, system_symbol, waypoint_symbol) do
    Tesla.get(client, "/v2/systems/#{system_symbol}/waypoints/#{waypoint_symbol}/shipyard")
  end

  def get_construction_site(client, system_symbol, waypoint_symbol) do
    Tesla.get(client, "/v2/systems/#{system_symbol}/waypoints/#{waypoint_symbol}/construction")
  end
end
