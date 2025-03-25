defmodule SpacetradersClient.Systems do
  use Nebulex.Caching

  alias SpacetradersClient.Cache

  @decorate cacheable(cache: Cache, key: {:system, system_symbol})
  def get_system(client, system_symbol) do
    Tesla.get(client, "/v2/systems/#{system_symbol}")
  end

  @decorate cacheable(cache: Cache, key: {:waypoint, waypoint_symbol})
  def get_waypoint(client, system_symbol, waypoint_symbol) do
    Tesla.get(client, "/v2/systems/#{system_symbol}/waypoints/#{waypoint_symbol}")
  end

  @decorate cacheable(cache: Cache, key: {:waypoints, system_symbol, opts})
  def list_waypoints(client, system_symbol, opts \\ []) do
    params = URI.encode_query(opts)
    Tesla.get(client, "/v2/systems/#{system_symbol}/waypoints?#{params}")
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

  def supply_construction_site(
        client,
        system_symbol,
        waypoint_symbol,
        ship_symbol,
        trade_symbol,
        units
      ) do
    Tesla.post(
      client,
      "/v2/systems/#{system_symbol}/waypoints/#{waypoint_symbol}/construction/supply",
      %{shipSymbol: ship_symbol, tradeSymbol: trade_symbol, units: units}
    )
  end
end
