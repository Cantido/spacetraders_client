defmodule SpacetradersClient.Ship do
  alias SpacetradersClient.Game

  def possible_travel_modes(ship, distance) do
    ~w(CRUISE DRIFT)
    |> Enum.filter(fn mode ->
      fuel_cost(distance)[mode] <= ship["fuel"]["capacity"]
    end)
  end

  def best_travel_mode(ship, distance) do
    possible_travel_modes(ship, distance)
    |> Enum.sort_by(fn mode ->
      travel_time(ship, distance)[mode]
    end)
    |> List.first()
  end


  def travel_time(ship, distance) do
    speed = ship["engine"]["speed"]

    %{
      "CRUISE" => 25,
      "DRIFT" => 250,
      "BURN" => 12.5,
      "STEALTH" => 30
    }
    |> Map.new(fn {mode, multiplier} ->
      d = Float.round(max(1.0, distance * 1.0))

      time =
        (d * (multiplier / speed) + 15)
        |> Float.round()
        |> trunc()

      {mode, time}
    end)
  end

  def fuel_cost(distance) do
    %{
      "CRUISE" => max(1, trunc(Float.round(distance))),
      "DRIFT" => 1,
      "BURN" => max(2, 2 * trunc(Float.round(distance))),
      "STEALTH" => max(1, trunc(Float.round(distance)))
    }
  end

  def fuel_cost(ship, distance) do
    case ship["nav"]["flightMode"] do
      "CRUISE" -> max(1, trunc(Float.round(distance)))
      "DRIFT" -> 1
      "BURN" -> max(2, 2 * trunc(Float.round(distance)))
      "STEALTH" -> max(1, trunc(Float.round(distance)))
    end
  end

  def sufficient_fuel_for_travel?(ship, %Game{} = game, waypoint) when is_map(ship) and is_map(waypoint) do
    d = Game.distance_between(game, get_in(ship, ~w(nav waypointSymbol)), waypoint["symbol"])


    fuel_qty = fuel_cost(ship, d)

    ship["fuel"]["current"] >= fuel_qty
  end

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

  def traveling?(ship) do
    if arrival = get_in(ship, ~w(nav route arrival)) do
      {:ok, arrival, _} = DateTime.from_iso8601(arrival)

      DateTime.before?(DateTime.utc_now(), arrival)
    else
      false
    end
  end

  def has_mining_laser?(ship) do
    Enum.map(ship["mounts"], fn m -> m["symbol"] end)
    |> Enum.any?(fn mount ->
      mount in ~w(MOUNT_MINING_LASER_I MOUNT_MINING_LASER_II MOUNT_MINING_LASER_III)
    end)
  end

  def has_gas_siphon?(ship) do
    Enum.map(ship["mounts"], fn m -> m["symbol"] end)
    |> Enum.any?(fn mount ->
      mount in ~w(MOUNT_GAS_SIPHON_I MOUNT_GAS_SIPHON_II MOUNT_GAS_SIPHON_III)
    end)
  end

  def has_cargo_capacity?(ship) do
    ship["cargo"]["units"] < ship["cargo"]["capacity"]
  end
end
