defmodule SpacetradersClient.Behaviors do
  alias SpacetradersClient.ShipTask
  alias SpacetradersClient.Survey
  alias SpacetradersClient.Game
  alias SpacetradersClient.Fleet

  alias Taido.Node
  alias Phoenix.PubSub

  require Logger

  @pubsub SpacetradersClient.PubSub


  def for_task(%ShipTask{name: :selling} = task) do
    Node.sequence([
      wait_for_transit(),
      travel_to_waypoint(task.args.waypoint_symbol, task.args.flight_mode),
      wait_for_transit(),
      dock_ship(),
      sell_cargo_item(task.args.trade_symbol, task.args.units)
    ])
  end

  def for_task(%ShipTask{name: :buying} = task) do
    Node.sequence([
      wait_for_transit(),
      travel_to_waypoint(task.args.start_wp),
      wait_for_transit(),
      dock_ship(),
      buy_cargo(task.args.trade_symbol, task.args.units)
    ])
  end

  def for_task(%ShipTask{name: :trade} = task) do
    Node.sequence([
      wait_for_transit(),
      travel_to_waypoint(task.args.start_wp, task.args.start_flight_mode),
      wait_for_transit(),
      dock_ship(),
      buy_cargo(task.args.trade_symbol, task.args.units),
      travel_to_waypoint(task.args.end_wp, task.args.transport_flight_mode),
      wait_for_transit(),
      dock_ship(),
      sell_cargo_item(task.args.trade_symbol, task.args.units)
    ])
  end

  def for_task(%ShipTask{name: :pickup} = task) do
    Node.sequence([
      wait_for_transit(),
      travel_to_waypoint(task.args.start_wp, task.args.start_flight_mode),
      wait_for_transit(),
      pickup_cargo(task.args.pickup_ship_symbol, task.args.trade_symbol, task.args.units),
      travel_to_waypoint(task.args.end_wp, task.args.transport_flight_mode),
      wait_for_transit(),
      dock_ship(),
      sell_cargo_item(task.args.trade_symbol, task.args.units)
    ])
  end

  def for_task(%ShipTask{name: :mine} = task) do
    Node.sequence([
      travel_to_waypoint(task.args.waypoint_symbol, "CRUISE"),
      wait_for_transit(),
      wait_for_ship_cooldown(),
      extract_resources()
    ])
  end

  def for_task(%ShipTask{name: :idle}) do
    Node.action(fn _ -> :success end)
  end


  def enter_orbit do
    Node.select([
      Node.condition(fn state ->
        ship = Game.ship(state.game, state.ship_symbol)

        ship["nav"]["status"] == "IN_ORBIT"
      end),
      Node.action(fn state ->
        case Fleet.orbit_ship(state.game.client, state.ship_symbol) do
          {:ok, %{status: 200, body: body}} ->
            game =
              Game.update_ship!(state.game, state.ship_symbol, fn ship ->
                Map.put(ship, "nav", body["data"]["nav"])
              end)

            PubSub.broadcast(@pubsub, "agent:#{game.agent["symbol"]}", {:ship_nav_updated, state.ship_symbol, body["data"]["nav"]})

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
      Node.action(fn state ->
        case Fleet.dock_ship(state.game.client, state.ship_symbol) do
          {:ok, %{status: 200, body: body}} ->
            game =
              Game.update_ship!(state.game, state.ship_symbol, fn ship ->
                Map.put(ship, "nav", body["data"]["nav"])
              end)

            PubSub.broadcast(@pubsub, "agent:#{game.agent["symbol"]}", {:ship_nav_updated, state.ship_symbol, body["data"]["nav"]})

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

        Node.action(fn state ->
          case Fleet.refuel_ship(state.game.client, state.ship_symbol) do
            {:ok, %{status: 200, body: body}} ->
              game =
                Game.update_ship!(state.game, state.ship_symbol, fn ship ->
                  Map.put(ship, "nav", body["data"]["fuel"])
                end)
                |> Map.put(:agent, body["data"]["agent"])

              PubSub.broadcast(@pubsub, "agent:#{game.agent["symbol"]}", {:agent_updated, body["data"]["agent"]})
              PubSub.broadcast(@pubsub, "agent:#{game.agent["symbol"]}", {:ship_fuel_updated, state.ship_symbol, body["data"]["fuel"]})

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
      arrival = get_in(ship, ~w(nav route arrival))

      if arrival && ship["nav"]["status"] == "IN_TRANSIT" do
        {:ok, arrival_time, _} = DateTime.from_iso8601(arrival)

        if DateTime.before?(DateTime.utc_now(), arrival_time) do
          :running
        else
          {:ok, %{status: 200, body: body}} = Fleet.get_ship_nav(state.game.client, state.ship_symbol)

          game =
            Game.update_ship!(state.game, state.ship_symbol, fn ship ->
              ship
              |> Map.put("nav", body["data"])
            end)

          PubSub.broadcast(@pubsub, "agent:#{game.agent["symbol"]}", {:ship_nav_updated, state.ship_symbol, body["data"]})


          {:success, Map.put(state, :game, game)}
        end
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

      Node.action(fn state ->
        ship = Game.ship(state.game, state.ship_symbol)

        best_survey =
          Game.surveys(state.game, ship["nav"]["waypointSymbol"])
          |> Enum.sort_by(fn survey ->
            Survey.profitability(survey, fn trade_symbol ->
              case Game.best_selling_market_price(state.game, ship["nav"]["systemSymbol"], trade_symbol) do
                nil -> 0
                {_mkt, price} -> price
              end
            end)
          end, :desc)
          |> List.first()

        case Fleet.extract_resources(state.game.client, state.ship_symbol, best_survey) do
          {:ok, %{status: 201, body: body}} ->
            game =
              Game.update_ship!(state.game, state.ship_symbol, fn ship ->
                ship
                |> Map.put("cargo", body["data"]["cargo"])
                |> Map.put("cooldown", body["data"]["cooldown"])
              end)

            PubSub.broadcast(@pubsub, "agent:#{game.agent["symbol"]}", {:ship_cargo_updated, state.ship_symbol, body["data"]["cargo"]})
            PubSub.broadcast(@pubsub, "agent:#{game.agent["symbol"]}", {:ship_cooldown_updated, state.ship_symbol, body["data"]["cooldown"]})

            {:success, Map.put(state, :game, game)}


          {:ok, %{status: 409, body: %{"error" => %{"code" => 4224}}}} ->
            game =
              Game.delete_survey(state.game, ship["nav"]["waypointSymbol"], best_survey["signature"])

            {:failure, Map.put(state, :game, game)}

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

        Node.action(fn state ->
          ship = Game.ship(state.game, state.ship_symbol)

          cargo_to_jettison =
            Enum.filter(ship["cargo"]["inventory"], fn cargo_item ->
              case Game.best_selling_market_price(state.game, ship["nav"]["systemSymbol"], cargo_item["symbol"]) do
                nil ->
                  true
                {_mkt, price} ->
                  price == 0
              end
            end)
            |> List.first()

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

  def travel_to_waypoint(waypoint_symbol, flight_mode \\ "CRUISE") do
    Node.select([
      Node.condition(fn state ->
        ship = Game.ship(state.game, state.ship_symbol)

        ship["nav"]["waypointSymbol"] == waypoint_symbol
      end),

      Node.sequence([
        refuel(),

        enter_orbit(),

        Node.select([
          Node.condition(fn state ->
            ship = Game.ship(state.game, state.ship_symbol)

            ship["nav"]["flightMode"] == flight_mode
          end),

          Node.action(fn state ->
            case Fleet.set_flight_mode(state.game.client, state.ship_symbol, flight_mode) do
              {:ok, %{status: 200, body: body}} ->
                game =
                  Game.update_ship!(state.game, state.ship_symbol, fn ship ->
                    ship
                    |> Map.put("nav", body["data"]["nav"])
                  end)

                PubSub.broadcast(@pubsub, "agent:#{game.agent["symbol"]}", {:ship_nav_updated, state.ship_symbol, body["data"]["nav"]})

                {:success, %{state | game: game}}

              err ->
                Logger.error("Failed to set flight mode: #{inspect err}")
                {:failure, state}
            end
          end)
        ]),

        Node.action(fn state ->
          case Fleet.navigate_ship(state.game.client, state.ship_symbol, waypoint_symbol) do
            {:ok, %{status: 200, body: body}} ->
              game =
                Game.update_ship!(state.game, state.ship_symbol, fn ship ->
                  ship
                  |> Map.put("nav", body["data"]["nav"])
                  |> Map.put("fuel", body["data"]["fuel"])
                end)

              PubSub.broadcast(@pubsub, "agent:#{game.agent["symbol"]}", {:ship_nav_updated, state.ship_symbol, body["data"]["nav"]})
              PubSub.broadcast(@pubsub, "agent:#{game.agent["symbol"]}", {:ship_fuel_updated, state.ship_symbol, body["data"]["fuel"]})

              {:success, %{state | game: game}}

            {:ok, %{status: 400, body: %{"error" => %{"code" => 4204}}}} ->
              :success

            err ->
              Logger.error("Failed to navigate ship: #{inspect err}")
              {:failure, state}
          end
        end)
      ])
    ])
  end

  def sell_cargo_item(trade_symbol, units) do
    Node.sequence([
      Node.action(fn state ->
        ship = Game.ship(state.game, state.ship_symbol)

        cargo_to_sell =
          Enum.find(ship["cargo"]["inventory"], fn cargo_item ->
            cargo_item["symbol"] == trade_symbol
          end)

        if cargo_to_sell do
          case Fleet.sell_cargo(state.game.client, state.ship_symbol, trade_symbol, units) do
            {:ok, %{status: 201, body: body}} ->
              game =
                Game.update_ship!(state.game, state.ship_symbol, fn ship ->
                  ship
                  |> Map.put("cargo", body["data"]["cargo"])
                end)
                |> Map.put(:agent, body["data"]["agent"])

              PubSub.broadcast(@pubsub, "agent:#{game.agent["symbol"]}", {:agent_updated, body["data"]["agent"]})
              PubSub.broadcast(@pubsub, "agent:#{game.agent["symbol"]}", {:ship_cargo_updated, state.ship_symbol, body["data"]["cargo"]})

              {:success, %{state | game: game}}

            err ->
              Logger.error("Failed to sell cargo: #{inspect err}")
              {:failure, state}
          end
        else
          :success
        end
      end),
      Node.action(fn state ->
        ship = Game.ship(state.game, state.ship_symbol)
        game = Game.load_market!(state.game, ship["nav"]["systemSymbol"], ship["nav"]["waypointSymbol"])

        {:success, %{state | game: game}}
      end)
    ])
  end

  def pickup_cargo(source_ship_symbol, trade_symbol, units) do
    Node.action(fn state ->
      case Fleet.transfer_cargo(state.game.client, source_ship_symbol, state.ship_symbol, trade_symbol, units) do
        {:ok, %{status: 200, body: body}} ->
          game =
            Game.update_ship!(state.game, source_ship_symbol, fn ship ->
              ship
              |> Map.put("cargo", body["data"]["cargo"])
            end)
            |> Game.load_ship_cargo!(state.ship_symbol)

          receiving_ship = Game.ship(game, state.ship_symbol)

          PubSub.broadcast(@pubsub, "agent:#{game.agent["symbol"]}", {:ship_updated, state.ship_symbol, receiving_ship})
          PubSub.broadcast(@pubsub, "agent:#{game.agent["symbol"]}", {:ship_cargo_updated, source_ship_symbol, body["data"]["cargo"]})

          {:success, Map.put(state, :game, game)}

        err ->
          Logger.error("Failed to transfer cargo: #{inspect err}")
          {:failure, state}
      end
    end)
  end

  def transfer_cargo_item(destination_ship_symbol) do
    Node.action(fn state ->
      ship = Game.ship(state.game, state.ship_symbol)

      if cargo_to_transfer = List.first(ship["cargo"]["inventory"]) do
        case Fleet.transfer_cargo(state.game.client, state.ship_symbol, destination_ship_symbol, cargo_to_transfer["symbol"], cargo_to_transfer["units"]) do
          {:ok, %{status: 200, body: body}} ->
            game =
              Game.update_ship!(state.game, state.ship_symbol, fn ship ->
                ship
                |> Map.put("cargo", body["data"]["cargo"])
              end)
              |> Game.load_ship_cargo!(destination_ship_symbol)

            {:success, Map.put(state, :game, game)}

          err ->
            Logger.error("Failed to transfer cargo: #{inspect err}")
            {:failure, state}
        end
      else
        :success
      end
    end)
  end

  def create_survey do
    Node.sequence([
      wait_for_ship_cooldown(),
      Node.action(fn state ->
        case Fleet.create_survey(state.game.client, state.ship_symbol) do
          {:ok, %{status: 201, body: body}} ->
            game =
              Enum.reduce(body["data"]["surveys"], state.game, fn survey, game ->
                Game.add_survey(game, survey)
              end)
              |> Game.update_ship!(state.ship_symbol, fn ship ->
                Map.put(ship, "cooldown", body["data"]["cooldown"])
              end)

            {:success, %{state | game: game}}

          {:ok, %{status: 409, body: body}}->

            game =
              Game.update_ship!(state.game, state.ship_symbol, fn ship ->
                Map.put(ship, "cooldown", body["error"]["data"]["cooldown"])
              end)

            {:failure, %{state | game: game}}

          err ->
            Logger.error("Failed to create survey: #{inspect err}")

            :failure
        end
      end)
    ])
  end

  def buy_cargo(trade_symbol, units) do
    Node.sequence([
      Node.action(fn state ->
        case Fleet.purchase_cargo(state.game.client, state.ship_symbol, trade_symbol, units) do
          {:ok, %{status: 201, body: body}} ->
            game =
              Game.update_ship!(state.game, state.ship_symbol, fn ship ->
                ship
                |> Map.put("cargo", body["data"]["cargo"])
              end)
              |> Map.put(:agent, body["data"]["agent"])

            PubSub.broadcast(@pubsub, "agent:#{game.agent["symbol"]}", {:agent_updated, body["data"]["agent"]})
            PubSub.broadcast(@pubsub, "agent:#{game.agent["symbol"]}", {:ship_cargo_updated, state.ship_symbol, body["data"]["cargo"]})

            {:success, %{state | game: game}}

          err ->
            Logger.error("Failed to sell cargo: #{inspect err}")
            {:failure, state}
        end
      end),
      Node.action(fn state ->
        ship = Game.ship(state.game, state.ship_symbol)
        game = Game.load_market!(state.game, ship["nav"]["systemSymbol"], ship["nav"]["waypointSymbol"])

        {:success, %{state | game: game}}
      end)
    ])
  end

  def load_markets do
    Node.action(fn state ->
      game = Game.load_markets!(state.game)
      {:success, %{state | game: game}}
    end)
  end
end
