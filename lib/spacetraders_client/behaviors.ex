defmodule SpacetradersClient.Behaviors do
  alias SpacetradersClient.Game
  alias SpacetradersClient.Fleet

  alias Taido.Node

  require Logger

  def enter_orbit do
    Node.select([
      Node.condition(fn state ->
        ship = Game.ship(state.game, state.ship_symbol)

        ship["nav"]["status"] == "IN_ORBIT"
      end),
      Node.async_action(fn state ->
        case Fleet.orbit_ship(state.game.client, state.ship_symbol) do
          {:ok, %{status: 200, body: body}} ->
            game =
              Game.update_ship!(state.game, state.ship_symbol, fn ship ->
                Map.put(ship, "nav", body["data"]["nav"])
              end)

            {:success, %{state | game: game}}

          err ->
            Logger.error("Failed to orbit ship: #{inspect err}")
            {:failure, state}
        end
      end)
    ])
  end

  def dock_ship do
    Node.select([
      Node.condition(fn state ->
        ship = Game.ship(state.game, state.ship_symbol)

        ship["nav"]["status"] == "DOCKED"
      end),
      Node.async_action(fn state ->
        case Fleet.dock_ship(state.game.client, state.ship_symbol) do
          {:ok, %{status: 200, body: body}} ->
            game =
              Game.update_ship!(state.game, state.ship_symbol, fn ship ->
                Map.put(ship, "nav", body["data"]["nav"])
              end)

            {:success, %{state | game: game}}

          err ->
            Logger.error("Failed to dock ship: #{inspect err}")
            {:failure, state}
        end
      end)
    ])
  end

  def refuel do
    Node.select([
      Node.condition(fn state ->
        ship = Game.ship(state.game, state.ship_symbol)

        ship["fuel"]["current"] == ship["fuel"]["capacity"]
      end),

      Node.sequence([
        dock_ship(),

        Node.async_action(fn state ->
          case Fleet.refuel_ship(state.game.client, state.ship_symbol) do
            {:ok, %{status: 200, body: body}} ->
              game =
                Game.update_ship!(state.game, state.ship_symbol, fn ship ->
                  Map.put(ship, "nav", body["data"]["fuel"])
                end)

              {:success, %{state | game: game}}

            err ->
              Logger.error("Failed to refuel ship: #{inspect err}")
              {:failure, state}
          end
        end)
      ])
    ])
  end

  def wait_for_transit do
    Node.action(fn state ->
      ship = Game.ship(state.game, state.ship_symbol)

      {:ok, arrival_time, _} = DateTime.from_iso8601(ship["nav"]["route"]["arrival"])

      if DateTime.before?(DateTime.utc_now(), arrival_time) do
        :running
      else
        :success
      end
    end)
  end

  def wait_for_ship_cooldown do
    Node.action(fn state ->
      ship = Game.ship(state.game, state.ship_symbol)

      if ship["cooldown"]["expiration"] do
        {:ok, expiration, _} = DateTime.from_iso8601(ship["cooldown"]["expiration"])

        if DateTime.before?(DateTime.utc_now(), expiration) do
          :running
        else
          :success
        end
      else
        :success
      end
    end)
  end

  def extract_resources do
    Node.sequence([
      enter_orbit(),

      wait_for_ship_cooldown(),

      Node.async_action(fn state ->
        case Fleet.extract_resources(state.game.client, state.ship_symbol) do
          {:ok, %{status: 201, body: body}} ->
            game =
              Game.update_ship!(state.game, state.ship_symbol, fn ship ->
                ship
                |> Map.put("cargo", body["data"]["cargo"])
                |> Map.put("cooldown", body["data"]["cooldown"])
              end)

            {:success, %{state | game: game}}

          err ->
            Logger.error("Failed to extract resources: #{inspect err}")
            {:failure, state}
        end
      end)
    ])
  end

  def cargo_full do
    Node.condition(fn state ->
      ship = Game.ship(state.game, state.ship_symbol)

      ship["cargo"]["units"] == ship["cargo"]["capacity"]
    end)
  end

  def cargo_empty do
    Node.condition(fn state ->
      ship = Game.ship(state.game, state.ship_symbol)

      ship["cargo"]["units"] == 0
    end)
  end

  def jettison_cargo do
    Node.select([
      cargo_empty(),

      Node.sequence([
        enter_orbit(),

        Node.async_action(fn state ->
          ship = Game.ship(state.game, state.ship_symbol)
          market = Game.market(state.game, "X1-BU22", "X1-BU22-H54")

          cargo_to_jettison = List.first(cargo_to_jettison(ship, market))

          if cargo_to_jettison do
            case Fleet.jettison_cargo(state.game.client, state.ship_symbol, cargo_to_jettison["symbol"], cargo_to_jettison["units"]) do
              {:ok, %{status: 200, body: body}} ->
                game =
                  Game.update_ship!(state.game, state.ship_symbol, fn ship ->
                    ship
                    |> Map.put("cargo", body["data"]["cargo"])
                  end)

                {:success, %{state | game: game}}

              err ->
                Logger.error("Failed to jettison cargo: #{inspect err}")
                {:failure, state}
            end
          else
            :success
          end
        end),

        Node.invert(cargo_empty())
      ])
    ])
  end

  def travel_to_waypoint(waypoint_symbol) do
    Node.select([
      Node.condition(fn state ->
        ship = Game.ship(state.game, state.ship_symbol)

        ship["nav"]["waypointSymbol"] == waypoint_symbol
      end),

      Node.sequence([
        refuel(),

        enter_orbit(),

        Node.async_action(fn state ->
          case Fleet.navigate_ship(state.game.client, state.ship_symbol, waypoint_symbol) do
            {:ok, %{status: 200, body: body}} ->
              game =
                Game.update_ship!(state.game, state.ship_symbol, fn ship ->
                  ship
                  |> Map.put("nav", body["data"]["nav"])
                  |> Map.put("fuel", body["data"]["fuel"])
                end)

              {:success, %{state | game: game}}

            err ->
              Logger.error("Failed to navigate ship: #{inspect err}")
              {:failure, state}
          end
        end)
      ])
    ])
  end

  def has_saleable_cargo do
    Node.sequence([
      Node.condition(fn state ->
        ship = Game.ship(state.game, state.ship_symbol)
        market = Game.market(state.game, "X1-BU22", "X1-BU22-H54")

        Enum.any?(ship["cargo"]["inventory"], fn cargo_item ->
          trade_good = Enum.find(market["tradeGoods"], fn t -> t["symbol"] == cargo_item["symbol"] end)

          trade_good && trade_good["sellPrice"] > 0
        end)
      end)
    ])
  end

  def sell_cargo_item do
    Node.async_action(fn state ->
      ship = Game.ship(state.game, state.ship_symbol)
      market = Game.market(state.game, "X1-BU22", "X1-BU22-H54")

      cargo_to_sell =
        Enum.find(ship["cargo"]["inventory"], fn cargo_item ->
          trade_good = Enum.find(market["tradeGoods"], fn t -> t["symbol"] == cargo_item["symbol"] end)

          trade_good && trade_good["sellPrice"] > 0
        end)

      if cargo_to_sell do
        case Fleet.sell_cargo(state.game.client, state.ship_symbol, cargo_to_sell["symbol"], cargo_to_sell["units"]) do
          {:ok, %{status: 201, body: body}} ->
            game =
              Game.update_ship!(state.game, state.ship_symbol, fn ship ->
                ship
                |> Map.put("cargo", body["data"]["cargo"])
              end)

            {:success, %{state | game: game}}

          err ->
            Logger.error("Failed to sell cargo: #{inspect err}")
            {:failure, state}
        end
      else
        :success
      end
    end)
  end

  defp cargo_to_jettison(ship, market) do
    Enum.reject(ship["cargo"]["inventory"], fn cargo_item ->
      trade_good = Enum.find(market["tradeGoods"], fn t -> t["symbol"] == cargo_item["symbol"] end)

      trade_good && trade_good["sellPrice"] > 0
    end)
  end

  def transfer_cargo_item(destination_ship_symbol) do
    Node.async_action(fn state ->
      ship = Game.ship(state.game, state.ship_symbol)

      if cargo_to_transfer = List.first(ship["cargo"]["inventory"]) do
        case Fleet.transfer_cargo(state.game.client, state.ship_symbol, destination_ship_symbol, cargo_to_transfer["symbol"], cargo_to_transfer["units"]) do
          {:ok, %{status: 200, body: body}} ->
            game =
              Game.update_ship!(state.game, state.ship_symbol, fn ship ->
                ship
                |> Map.put("cargo", body["data"]["cargo"])
              end)

            {:success, %{state | game: game}}

          err ->
            Logger.error("Failed to transfer cargo: #{inspect err}")
            {:failure, state}
        end
      else
        :success
      end
    end)
  end
end
