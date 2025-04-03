defmodule SpacetradersClient.Behaviors do
  alias SpacetradersClient.Systems
  alias SpacetradersClient.Automation.ShipTask
  alias SpacetradersClient.Survey
  alias SpacetradersClient.Game
  alias SpacetradersClient.Fleet
  alias SpacetradersClient.Finance
  alias SpacetradersClient.Game.Agent
  alias SpacetradersClient.Game.Ship
  alias SpacetradersClient.Repo

  alias Taido.Node
  alias Phoenix.PubSub

  require Logger

  @pubsub SpacetradersClient.PubSub

  def for_task(%ShipTask{name: "goto"} = task) do
    Node.sequence([
      wait_for_transit(),
      refuel(),
      travel_to_waypoint(ShipTask.arg(task, "waypoint_symbol"), flight_mode: "CRUISE")
    ])
  end

  def for_task(%ShipTask{name: "selling"} = task) do
    Node.sequence([
      wait_for_transit(),
      refuel(min_fuel: ShipTask.arg(task, "fuel_consumed")),
      travel_to_waypoint(ShipTask.arg(task, "waypoint_symbol"),
        flight_mode: stringify_flight_mode(ShipTask.arg(task, "flight_mode"))
      ),
      wait_for_transit(),
      dock_ship(),
      sell_cargo_item(ShipTask.arg(task, "trade_symbol"), ShipTask.arg(task, "units"))
    ])
  end

  def for_task(%ShipTask{name: "trade"} = task) do
    whole_volume_count = div(ShipTask.arg(task, "units"), ShipTask.arg(task, "volume"))
    units_in_last_volume = rem(ShipTask.arg(task, "units"), ShipTask.arg(task, "volume"))

    whole_volume_amounts =
      Stream.repeatedly(fn -> ShipTask.arg(task, "volume") end)
      |> Stream.take(whole_volume_count)
      |> Enum.to_list()

    last_volume_amounts =
      if units_in_last_volume == 0 do
        []
      else
        [units_in_last_volume]
      end

    volume_amounts_to_trade = whole_volume_amounts ++ last_volume_amounts

    Node.sequence([
      wait_for_transit(),
      refuel(min_fuel: ShipTask.arg(task, "start_fuel_consumed")),
      travel_to_waypoint(ShipTask.arg(task, "start_wp"),
        flight_mode: stringify_flight_mode(ShipTask.arg(task, "start_flight_mode")),
        fuel_min: ShipTask.arg(task, "start_fuel_consumed")
      ),
      wait_for_transit(),
      dock_ship(),
      Node.sequence(
        Enum.map(volume_amounts_to_trade, fn units ->
          buy_cargo(ShipTask.arg(task, "trade_symbol"), units,
            max_price: ShipTask.arg(task, "max_purchase_price")
          )
        end)
      ),
      refuel(min_fuel: ShipTask.arg(task, "end_fuel_consumed")),
      travel_to_waypoint(ShipTask.arg(task, "end_wp"),
        flight_mode: stringify_flight_mode(ShipTask.arg(task, "end_flight_mode")),
        fuel_min: ShipTask.arg(task, "end_fuel_consumed")
      ),
      wait_for_transit(),
      dock_ship(),
      sell_cargo_item(ShipTask.arg(task, "trade_symbol"), ShipTask.arg(task, "units"),
        min_price: ShipTask.arg(task, "min_sell_price")
      )
    ])
  end

  def for_task(%ShipTask{name: "pickup"} = task) do
    Node.sequence([
      wait_for_transit(),
      refuel(min_fuel: ShipTask.arg(task, "fuel_consumed")),
      travel_to_waypoint(ShipTask.arg(task, "start_wp"),
        flight_mode: stringify_flight_mode(ShipTask.arg(task, "start_flight_mode"))
      ),
      wait_for_transit(),
      Node.sequence(
        ShipTask.arg(task, "ship_pickups")
        |> Jason.decode!()
        |> Enum.map(fn {pickup_ship_symbol, units} ->
          pickup_cargo(pickup_ship_symbol, ShipTask.arg(task, "trade_symbol"), units)
        end)
      )
    ])
  end

  def for_task(%ShipTask{name: "deliver_construction_materials"} = task) do
    if ShipTask.arg(task, "direct_delivery?") == "true" do
      Node.sequence([
        refuel(min_fuel: ShipTask.arg(task, "ship_to_site_fuel_consumed")),
        travel_to_waypoint(ShipTask.arg(task, "waypoint_symbol")),
        wait_for_transit(),
        dock_ship(),
        deliver_construction_materials(
          ShipTask.arg(task, "trade_symbol"),
          ShipTask.arg(task, "units")
        )
      ])
    else
      Node.sequence([
        wait_for_transit(),
        refuel(min_fuel: ShipTask.arg(task, "ship_to_market_fuel_consumed")),
        travel_to_waypoint(ShipTask.arg(task, "market_waypoint")),
        wait_for_transit(),
        dock_ship(),
        buy_cargo(ShipTask.arg(task, "trade_symbol"), ShipTask.arg(task, "units")),
        refuel(min_fuel: ShipTask.arg(task, "market_to_site_fuel_consumed")),
        travel_to_waypoint(ShipTask.arg(task, "waypoint_symbol")),
        wait_for_transit(),
        dock_ship(),
        deliver_construction_materials(
          ShipTask.arg(task, "trade_symbol"),
          ShipTask.arg(task, "units")
        )
      ])
    end
  end

  def for_task(%ShipTask{name: "mine"} = task) do
    Node.sequence([
      refuel(min_fuel: ShipTask.arg(task, "fuel_consumed")),
      travel_to_waypoint(ShipTask.arg(task, "waypoint_symbol"), flight_mode: "CRUISE"),
      wait_for_transit(),
      wait_for_ship_cooldown(),
      extract_resources()
    ])
  end

  def for_task(%ShipTask{name: "siphon_resources"} = task) do
    Node.sequence([
      refuel(min_fuel: ShipTask.arg(task, "fuel_consumed")),
      travel_to_waypoint(ShipTask.arg(task, "waypoint_symbol"), flight_mode: "CRUISE"),
      wait_for_transit(),
      wait_for_ship_cooldown(),
      siphon_resources()
    ])
  end

  def for_task(%ShipTask{name: "idle"}) do
    Node.action(fn _ -> :success end)
  end

  defp stringify_flight_mode(:cruise), do: "CRUISE"
  defp stringify_flight_mode(:drift), do: "DRIFT"
  defp stringify_flight_mode(:burn), do: "BURN"
  defp stringify_flight_mode(:stealth), do: "STEALTH"
  defp stringify_flight_mode("cruise"), do: "CRUISE"
  defp stringify_flight_mode("drift"), do: "DRIFT"
  defp stringify_flight_mode("burn"), do: "BURN"
  defp stringify_flight_mode("stealth"), do: "STEALTH"

  def enter_orbit(ship_symbol) do
    Node.select([
      Node.condition(fn _state ->
        ship = Repo.get_by(Ship, symbol: ship_symbol)

        ship.nav_status == :in_orbit
      end),
      Node.action(fn state ->
        case Fleet.orbit_ship(state.client, ship_symbol) do
          {:ok, %{status: 200, body: body}} ->
            ship =
              Game.save_ship_nav!(ship_symbol, body["data"]["nav"])
              |> Repo.preload(:agent)

            PubSub.broadcast(
              @pubsub,
              "agent:#{ship.agent.symbol}",
              {:ship_updated, ship.symbol, ship}
            )

            {:success, state}

          err ->
            Logger.error("Failed to orbit ship: #{inspect(err)}")
            {:failure, state}
        end
      end)
    ])
  end

  def enter_orbit do
    Node.sequence([
      Node.invert(
        Node.condition(fn state ->
          ship = Repo.get_by(Ship, symbol: state.ship_symbol)

          ship.nav_status == :in_transit
        end)
      ),
      Node.select([
        Node.condition(fn state ->
          ship = Repo.get_by(Ship, symbol: state.ship_symbol)

          ship.nav_status == :in_orbit
        end),
        Node.action(fn state ->
          case Fleet.orbit_ship(state.client, state.ship_symbol) do
            {:ok, %{status: 200, body: body}} ->
              ship =
                Game.save_ship_nav!(state.ship_symbol, body["data"]["nav"])
                |> Repo.preload(:agent)

              PubSub.broadcast(
                @pubsub,
                "agent:#{ship.agent.symbol}",
                {:ship_updated, state.ship_symbol, ship}
              )

              {:success, state}

            {:ok, %{status: 400, body: %{"error" => %{"code" => 4214, "data" => data}}}} ->
              ship =
                Repo.get_by(Ship, symbol: state.ship_symbol)
                |> Ship.changeset(%{
                  nav_route_arrival_at: data["arrival"],
                  nav_status: "IN_TRANSIT"
                })

              PubSub.broadcast(
                @pubsub,
                "agent:#{ship.agent_symbol}",
                {:ship_updated, ship.symbol, ship}
              )

              {:failure, state}

            err ->
              Logger.error("Failed to orbit ship: #{inspect(err)}")
              {:failure, state}
          end
        end)
      ])
    ])
  end

  def dock_ship do
    Node.select([
      Node.condition(fn state ->
        ship = Repo.get_by(Ship, symbol: state.ship_symbol)

        ship.nav_status == :docked
      end),
      Node.action(fn state ->
        case Fleet.dock_ship(state.client, state.ship_symbol) do
          {:ok, %{status: 200, body: body}} ->
            ship =
              Game.save_ship_nav!(state.ship_symbol, body["data"]["nav"])
              |> Repo.preload(:agent)

            PubSub.broadcast(
              @pubsub,
              "agent:#{ship.agent.symbol}",
              {:ship_updated, state.ship_symbol, ship}
            )

            {:success, state}

          err ->
            Logger.error("Failed to dock ship: #{inspect(err)}")
            {:failure, state}
        end
      end)
    ])
  end

  def set_flight_mode(flight_mode) do
    Node.action(fn state ->
      case Fleet.set_flight_mode(state.client, state.ship_symbol, flight_mode) do
        {:ok, %{status: 200, body: body}} ->
          ship =
            Game.save_ship_nav!(state.ship_symbol, body["data"]["nav"])
            |> Repo.preload(:agent)

          PubSub.broadcast(
            @pubsub,
            "agent:#{ship.agent.symbol}",
            {:ship_updated, ship.symbol, ship}
          )

          {:success, state}

        err ->
          Logger.error("Failed to set flight mode: #{inspect(err)}")
          {:failure, state}
      end
    end)
  end

  def refuel(opts \\ []) do
    Node.sequence([
      Node.action(fn state ->
        ship = Repo.get_by(Ship, symbol: state.ship_symbol)

        min_fuel_opt = Keyword.get(opts, :min_fuel, :maximum)

        min_fuel =
          if min_fuel_opt == :maximum do
            ship.fuel_capacity
          else
            max(min_fuel_opt, ship.fuel_capacity - 100)
          end

        {:success, Map.put(state, :min_fuel, min_fuel)}
      end),
      Node.select([
        Node.condition(fn state ->
          ship = Repo.get_by(Ship, symbol: state.ship_symbol)
          ship.fuel_current >= state.min_fuel
        end),
        Node.sequence([
          travel_to_nearest_fuel(),
          wait_for_transit(),
          dock_ship(),
          Node.action(fn state ->
            case Game.refuel_ship(state.client, state.ship_symbol) do
              {:ok, _ship} ->
                :success

              {:error, reason} ->
                Logger.error("Failed to refuel ship: #{inspect(reason)}")

                :failure
            end
          end)
        ])
      ])
    ])
  end

  def travel_to_nearest_fuel do
    Node.sequence([
      fetch_nearest_fuel(),
      Node.select([
        at_fuel_market?(),
        Node.sequence([
          wait_for_transit(),
          enter_orbit(),
          navigate_ship_to_fuel_market()
        ]),
        Node.sequence([
          wait_for_transit(),
          enter_orbit(),
          set_flight_mode("DRIFT"),
          navigate_ship_to_fuel_market()
        ])
      ])
    ])
  end

  def fetch_nearest_fuel do
    Node.action(fn state ->
      ship = Repo.get_by(Ship, symbol: state.ship_symbol)

      fuel_wp = Game.nearest_fuel_waypoint(ship.nav_waypoint.symbol)

      if is_nil(fuel_wp) do
        raise "No fuel markets found in market data"
      end

      {:success, Map.put(state, :fuel_market, fuel_wp)}
    end)
  end

  def at_fuel_market? do
    Node.condition(fn state ->
      ship = Repo.get_by(Ship, symbol: state.ship_symbol) |> Repo.preload(:nav_waypoint)

      state.fuel_market.symbol == ship.nav_waypoint.symbol
    end)
  end

  def navigate_ship_to_fuel_market do
    Node.action(fn state ->
      case Game.navigate_ship(state.client, state.ship_symbol, state.fuel_market.symbol) do
        {:ok, _ship} ->
          :success

        {:error, %{"code" => 4204}} ->
          :success

        err ->
          Logger.error("Failed to navigate ship: #{inspect(err)}")
          :failure
      end
    end)
  end

  def wait_for_transit do
    Node.action(fn state ->
      ship = Repo.get_by(Ship, symbol: state.ship_symbol)
      arrival = ship.nav_route_arrival_at

      if arrival && ship.nav_status == :in_transit do
        if DateTime.before?(DateTime.utc_now(), arrival) do
          :running
        else
          {:ok, %{status: 200, body: body}} =
            Fleet.get_ship_nav(state.client, state.ship_symbol)

          ship =
            Game.save_ship_nav!(state.ship_symbol, body["data"])

          PubSub.broadcast(
            @pubsub,
            "agent:#{ship.agent_symbol}",
            {:ship_updated, state.ship_symbol, ship}
          )

          {:success, state}
        end
      else
        :success
      end
    end)
  end

  def wait_for_ship_cooldown do
    Node.action(fn state ->
      ship = Repo.get_by(Ship, symbol: state.ship_symbol)

      if expiration = ship.cooldown_expires_at do
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

  def siphon_resources do
    Node.sequence([
      enter_orbit(),
      wait_for_ship_cooldown(),
      Node.action(fn state ->
        ship =
          Repo.get_by(Ship, symbol: state.ship_symbol)
          |> Repo.preload(:agent, nav_waypoint: :system)

        case Fleet.siphon_resources(state.client, state.ship_symbol) do
          {:ok, %{status: 201, body: body}} ->
            Game.save_extraction!(ship.nav_waypoint.symbol, body["data"]["siphon"])
            Game.save_ship_cooldown!(ship.symbol, body["data"]["cooldown"])
            Game.save_ship_cargo!(ship.sybmol, body["data"]["cargo"])

            yield_symbol = get_in(body, ~w(data siphon yield symbol))
            yield_units = get_in(body, ~w(data siphon yield units))

            price =
              Game.average_purchase_price(ship.nav_waypoint.system.symbol, yield_symbol)

            value_of_material = trunc(price * yield_units)

            {:ok, _ledger} =
              Finance.post_journal(
                ship.agent_symbol,
                DateTime.utc_now(),
                "Extraction of #{yield_units} × #{yield_symbol} — #{state.ship_symbol} @ #{ship.nav_waypoint.symbol}",
                "Merchandise",
                "Natural Resources",
                value_of_material
              )

            {:ok, _ledger} =
              Finance.purchase_inventory_by_total(
                ship.agent.symbol,
                yield_symbol,
                DateTime.utc_now(),
                yield_units,
                value_of_material
              )

            PubSub.broadcast(
              @pubsub,
              "agent:#{ship.agent_symbol}",
              {:ship_updated, state.ship_symbol, ship}
            )

            {:success, state}

          {:ok, %{status: 400, body: %{"error" => %{"code" => 4228}}}} ->
            # Full cargo

            Game.load_ship!(state.client, state.ship_symbol)

            {:failure, state}

          err ->
            Logger.error("Failed to siphon resources: #{inspect(err)}")
            {:failure, state}
        end
      end)
    ])
  end

  def extract_resources do
    Node.sequence([
      enter_orbit(),
      wait_for_ship_cooldown(),
      Node.action(fn state ->
        ship =
          Repo.get_by(Ship, symbol: state.ship_symbol)
          |> Repo.preload(:agent, nav_waypoint: :system)

        best_survey =
          Game.surveys(ship.nav_waypoint.symbol)
          |> Enum.sort_by(
            fn survey ->
              Survey.profitability(survey, fn trade_symbol ->
                case Game.best_selling_market_price(
                       ship.nav_waypoint.system_symbol,
                       trade_symbol
                     ) do
                  nil -> 0
                  {_mkt, price} -> price
                end
              end)
            end,
            :desc
          )
          |> List.first()

        case Fleet.extract_resources(state.client, state.ship_symbol, best_survey) do
          {:ok, %{status: 201, body: body}} ->
            Game.save_extraction!(ship.nav_waypoint.symbol, body["data"]["extraction"])
            Game.save_ship_cooldown!(ship.symbol, body["data"]["cooldown"])
            Game.save_ship_cargo!(ship.sybmol, body["data"]["cargo"])

            yield_symbol = get_in(body, ~w(data extraction yield symbol))
            yield_units = get_in(body, ~w(data extraction yield units))

            price =
              Game.average_selling_price(ship.nav_waypoint.sytem.symbol, yield_symbol)

            value_of_material = trunc(price * yield_units)

            {:ok, _ledger} =
              Finance.post_journal(
                ship.agent_symbol,
                DateTime.utc_now(),
                "Extraction of #{yield_units} × #{yield_symbol} — #{state.ship_symbol} @ #{ship.nav_waypoint.symbol}",
                "Merchandise",
                "Natural Resources",
                value_of_material
              )

            {:ok, _ledger} =
              Finance.purchase_inventory_by_total(
                ship.agent.symbol,
                yield_symbol,
                DateTime.utc_now(),
                yield_units,
                value_of_material
              )

            PubSub.broadcast(
              @pubsub,
              "agent:#{ship.agent_symbol}",
              {:ship_updated, state.ship_symbol, ship}
            )

            {:success, state}

          {:ok, %{status: 409, body: %{"error" => %{"code" => 4224}}}} ->
            game =
              Game.delete_survey(
                ship.nav_waypoint.symbol,
                best_survey["signature"]
              )

            {:failure, Map.put(state, :game, game)}

          {:ok, %{status: 400, body: %{"error" => %{"code" => 4228}}}} ->
            # Full cargo

            Game.load_ship!(state.client, state.ship_symbol)

            {:failure, state}

          err ->
            Logger.error("Failed to extract resources: #{inspect(err)}")
            {:failure, state}
        end
      end)
    ])
  end

  def cargo_full do
    Node.condition(fn state ->
      ship = Repo.get_by(Ship, symbol: state.ship_symbol) |> Repo.preload(:cargo_items)

      Ship.cargo_current(ship) == ship.cargo_capacity
    end)
  end

  def cargo_empty do
    Node.condition(fn state ->
      ship = Repo.get_by(Ship, symbol: state.ship_symbol) |> Repo.preload(:cargo_items)

      Ship.cargo_current(ship) == 0
    end)
  end

  def jettison_cargo do
    Node.select([
      cargo_empty(),
      Node.sequence([
        enter_orbit(),
        Node.action(fn state ->
          ship =
            Repo.get_by(Ship, symbol: state.ship_symbol)
            |> Repo.preload([:cargo_items, :nav_waypoint])

          cargo_to_jettison =
            Enum.filter(ship.cargo_items, fn cargo_item ->
              case Game.best_selling_market_price(
                     ship.nav_waypoint.system_symbol,
                     cargo_item.item_symbol
                   ) do
                nil ->
                  true

                {_mkt, price} ->
                  price == 0
              end
            end)
            |> List.first()

          if cargo_to_jettison do
            case Fleet.jettison_cargo(
                   state.client,
                   state.ship_symbol,
                   cargo_to_jettison.item_symbol,
                   cargo_to_jettison.units
                 ) do
              {:ok, %{status: 200, body: body}} ->
                ship =
                  Game.save_ship_cargo!(state.ship_symbol, body["data"]["cargo"])
                  |> Repo.preload([:agent, :nav_waypoint])

                PubSub.broadcast(
                  @pubsub,
                  "agent:#{ship.agent.symbol}",
                  {:ship_updated, state.ship_symbol, ship}
                )

                {:success, state}

              err ->
                Logger.error("Failed to jettison cargo: #{inspect(err)}")
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

  def travel_to_waypoint(waypoint_symbol, opts \\ []) do
    flight_mode = Keyword.get(opts, :flight_mode, "CRUISE")

    Node.select([
      Node.condition(fn state ->
        ship = Repo.get_by(Ship, symbol: state.ship_symbol)

        ship.nav_waypoint.symbol == waypoint_symbol
      end),
      Node.sequence([
        enter_orbit(),
        Node.action(fn state ->
          case Fleet.set_flight_mode(state.client, state.ship_symbol, flight_mode) do
            {:ok, %{status: 200, body: body}} ->
              ship =
                Game.save_ship_nav!(state.ship_symbol, body["data"]["nav"])
                |> Repo.preload(:agent)

              PubSub.broadcast(
                @pubsub,
                "agent:#{ship.agent.symbol}",
                {:ship_updated, state.ship_symbol, ship}
              )

              {:success, state}

            err ->
              Logger.error("Failed to set flight mode: #{inspect(err)}")
              {:failure, state}
          end
        end),
        Node.action(fn state ->
          case Fleet.navigate_ship(state.client, state.ship_symbol, waypoint_symbol) do
            {:ok, %{status: 200, body: body}} ->
              Repo.get_by(Ship, symbol: state.ship_symbol)
              |> Ship.fuel_changeset(body["data"]["fuel"])
              |> Repo.update!()

              ship =
                Game.save_ship_nav!(state.ship_symbol, body["data"]["nav"])
                |> Repo.preload(:agent)

              PubSub.broadcast(
                @pubsub,
                "agent:#{ship.agent.symbol}",
                {:ship_updated, state.ship_symbol, ship}
              )

              {:success, state}

            {:ok, %{status: 400, body: %{"error" => %{"code" => 4204}}}} ->
              :success

            err ->
              Logger.error("Failed to navigate ship: #{inspect(err)}")
              {:failure, state}
          end
        end)
      ])
    ])
  end

  def sell_cargo_item(trade_symbol, units, opts \\ []) do
    Node.sequence([
      Node.action(fn state ->
        ship = Repo.get_by(Ship, symbol: state.ship_symbol) |> Repo.preload(:nav_waypoint)

        market =
          Repo.get_by(Market, symbol: ship.nav_waypoint.symbol) |> Repo.preload(:trade_goods)

        {:success, Map.put(state, :market, market)}
      end),
      Node.condition(fn state ->
        if min_price = Keyword.get(opts, :min_price) do
          state.market.trade_goods
          |> Enum.any?(fn trade_good ->
            trade_good.item_symbol == trade_symbol &&
              trade_good.sell_price >= min_price
          end)
        else
          true
        end
      end),
      Node.action(fn state ->
        ship = Repo.get_by(Ship, symbol: state.ship_symbol) |> Repo.preload(:cargo_items)

        cargo_to_sell =
          Enum.find(ship.cargo_items, fn cargo_item ->
            cargo_item.item_symbol == trade_symbol
          end)

        if cargo_to_sell do
          {:success, Map.put(state, :cargo_to_sell, cargo_to_sell)}
        else
          :failure
        end
      end),
      Node.action(fn state ->
        trade_good =
          state.market.trade_goods
          |> Enum.find(%{}, fn t -> t.item_symbol == trade_symbol end)

        market_volume = trade_good.trade_volume

        whole_volume_count = div(state.cargo_to_sell.units, market_volume)
        units_in_last_volume = rem(units, market_volume)

        whole_volume_amounts =
          Stream.repeatedly(fn -> market_volume end)
          |> Stream.take(whole_volume_count)
          |> Enum.to_list()

        last_volume_amounts =
          if units_in_last_volume == 0 do
            []
          else
            [units_in_last_volume]
          end

        volume_amounts_to_trade = whole_volume_amounts ++ last_volume_amounts

        Enum.reduce_while(volume_amounts_to_trade, {:success, state}, fn volume_amount,
                                                                         {_result, state} ->
          can_sell? =
            if min_price = Keyword.get(opts, :min_price) do
              state.market.trade_goods
              |> Enum.any?(fn trade_good ->
                trade_good.item_symbol == trade_symbol &&
                  trade_good.sell_price >= min_price
              end)
            else
              true
            end

          if can_sell? do
            case Fleet.sell_cargo(
                   state.client,
                   state.ship_symbol,
                   trade_symbol,
                   volume_amount
                 ) do
              {:ok, %{status: 201, body: body}} ->
                ship =
                  Game.save_ship_cargo!(state.ship_symbol, body["data"]["cargo"])
                  |> Repo.preload([:agent, [nav_waypoint: :system]])

                agent =
                  Repo.get_by(Agent, symbol: ship.agent.symbol)
                  |> Agent.changeset(body["data"]["agent"])
                  |> Repo.update!()

                Game.load_market!(
                  state.client,
                  ship.nav_waypoint.system.symbol,
                  ship.nav_waypoint.symbol
                )

                tx = body["data"]["transaction"]
                {:ok, ts, _} = DateTime.from_iso8601(tx["timestamp"])

                {:ok, _ledger} =
                  Finance.sell_inventory(
                    ship.agent_symbol,
                    trade_symbol,
                    ts,
                    tx["units"],
                    tx["totalPrice"]
                  )

                PubSub.broadcast(
                  @pubsub,
                  "agent:#{agent.symbol}",
                  {:agent_updated, agent}
                )

                PubSub.broadcast(
                  @pubsub,
                  "agent:#{ship.agent_symbol}",
                  {:ship_updated, state.ship_symbol, ship}
                )

                {:cont, {:success, state}}

              err ->
                Logger.error("Failed to sell cargo: #{inspect(err)}")
                {:halt, {:failure, state}}
            end
          else
            :failure
          end
        end)
      end)
    ])
  end

  def pickup_cargo(source_ship_symbol, trade_symbol, units) do
    Node.sequence([
      enter_orbit(source_ship_symbol),
      enter_orbit(),
      Node.action(fn state ->
        case Fleet.transfer_cargo(
               state.client,
               source_ship_symbol,
               state.ship_symbol,
               trade_symbol,
               units
             ) do
          {:ok, %{status: 200, body: body}} ->
            source_ship =
              Game.save_ship_cargo!(source_ship_symbol, body["data"]["cargo"])
              |> Repo.preload(:agent)

            Game.load_ship_cargo!(state.ship_symbol)

            receiving_ship =
              Repo.get_by(Ship, symbol: state.ship_symbol)
              |> Repo.preload(:agent)

            PubSub.broadcast(
              @pubsub,
              "agent:#{source_ship.agent.symbol}",
              {:ship_updated, source_ship.symbol, source_ship}
            )

            PubSub.broadcast(
              @pubsub,
              "agent:#{receiving_ship.agent.symbol}",
              {:ship_updated, receiving_ship.symbol, receiving_ship}
            )

            {:success, state}

          {:ok, %{status: 400, body: %{"error" => %{"code" => 4234, "data" => data}}}} ->
            source_ship_waypoint = Repo.get_by!(Waypoint, symbol: data["destinationSymbol"])

            source_ship =
              Repo.get_by!(Ship, symbol: data["shipSymbol"])
              |> Ecto.Changeset.put_assoc(:nav_waypoint, source_ship_waypoint)
              |> Repo.update!()
              |> Repo.preload(:agent)

            receiving_ship_waypoint = data["conflictingDestinationSymbol"]

            receiving_ship =
              Repo.get_by(Ship, symbol: data["targetShipSymbol"])
              |> Ecto.Changeset.put_assoc(:nav_waypoint, receiving_ship_waypoint)
              |> Repo.update!()
              |> Repo.preload(:agent)

            PubSub.broadcast(
              @pubsub,
              "agent:#{source_ship.agent.symbol}",
              {:ship_updated, source_ship.symbol, source_ship}
            )

            PubSub.broadcast(
              @pubsub,
              "agent:#{receiving_ship.agent.symbol}",
              {:ship_updated, receiving_ship.symbol, receiving_ship}
            )

            {:failure, state}

          err ->
            Logger.error("Failed to transfer cargo: #{inspect(err)}")
            {:failure, state}
        end
      end)
    ])
  end

  def create_survey do
    Node.sequence([
      wait_for_ship_cooldown(),
      Node.action(fn state ->
        case Fleet.create_survey(state.game.client, state.ship_symbol) do
          {:ok, %{status: 201, body: body}} ->
            Enum.each(body["data"]["surveys"], fn survey ->
              Game.add_survey(survey)
            end)

            ship =
              Repo.get_by(Ship, symbol: state.ship_symbol)
              |> Ship.cooldown_changeset(body["data"]["cooldown"])
              |> Repo.update!()

            PubSub.broadcast(
              @pubsub,
              "agent:#{ship.agent_symbol}",
              {:ship_updated, ship.symbol, ship}
            )

            {:success, state}

          {:ok, %{status: 409, body: body}} ->
            ship =
              Repo.get_by(Ship, symbol: state.ship_symbol)
              |> Ship.cooldown_changeset(body["error"]["data"]["cooldown"])
              |> Repo.update!()

            PubSub.broadcast(
              @pubsub,
              "agent:#{ship.agent_symbol}",
              {:ship_updated, ship.symbol, ship}
            )

            {:failure, state}

          err ->
            Logger.error("Failed to create survey: #{inspect(err)}")

            :failure
        end
      end)
    ])
  end

  def buy_cargo(trade_symbol, units, opts \\ []) do
    Node.sequence([
      Node.condition(fn state ->
        if max_price = Keyword.get(opts, :max_price) do
          ship = Repo.get_by(Ship, symbol: state.ship_symbol)

          market = Game.market(ship.nav_waypoint.symbol) |> Repo.preload(:trade_goods)

          market.trade_goods
          |> Enum.any?(fn trade_good ->
            trade_good.item_symbol == trade_symbol &&
              trade_good.purchase_price <= max_price
          end)
        else
          true
        end
      end),
      Node.action(fn state ->
        case Fleet.purchase_cargo(state.client, state.ship_symbol, trade_symbol, units) do
          {:ok, %{status: 201, body: body}} ->
            ship =
              Game.save_ship_cargo!(state.ship_symbol, body["data"]["cargo"])
              |> Repo.preload(:agent)

            agent =
              Repo.get_by(Agent, symbol: ship.agent.symbol)
              |> Agent.changeset(body["data"]["agent"])
              |> Repo.update!()

            tx = body["data"]["transaction"]
            {:ok, ts, _} = DateTime.from_iso8601(tx["timestamp"])

            {:ok, _ledger} =
              Finance.purchase_inventory_by_total(
                agent.symbol,
                trade_symbol,
                ts,
                tx["units"],
                tx["totalPrice"]
              )

            {:ok, _ledger} =
              Finance.post_journal(
                agent.symbol,
                ts,
                "#{tx["type"]} #{tx["tradeSymbol"]} × #{tx["units"]} @ #{tx["pricePerUnit"]}/u — #{state.ship_symbol} @ #{ship.nav_waypoint.symbol}",
                "Merchandise",
                "Cash",
                tx["totalPrice"]
              )

            PubSub.broadcast(
              @pubsub,
              "agent:#{agent.symbol}",
              {:agent_updated, agent}
            )

            PubSub.broadcast(
              @pubsub,
              "agent:#{ship.agent.symbol}",
              {:ship_updated, state.ship_symbol, ship}
            )

            {:success, state}

          err ->
            Logger.error("Failed to purchase cargo: #{inspect(err)}")
            {:failure, state}
        end
      end),
      Node.action(fn state ->
        ship = Repo.get_by(Ship, symbol: state.ship_symbol) |> Repo.preload(:nav_waypoint)

        Game.load_market!(state.client, ship.nav_waypoint.system_symbol, ship.nav_waypoint.symbol)

        {:success, state}
      end)
    ])
  end

  def deliver_construction_materials(trade_symbol, units) do
    Node.action(fn state ->
      ship =
        Repo.get_by(Ship, symbol: state.ship_symbol)
        |> Repo.preload(nav_waypoint: :system)

      case Systems.supply_construction_site(
             state.client,
             ship.nav_waypoint.system.symbol,
             ship.nav_waypoint.symbol,
             state.ship_symbol,
             trade_symbol,
             units
           ) do
        {:ok, %{status: 201, body: body}} ->
          ship =
            Game.save_ship_cargo!(state.ship_symbol, body["data"]["cargo"])
            |> Repo.preload(:agent)

          Game.load_construction_site!(
            state.client,
            ship.nav_waypoint.system.symbol,
            ship.nav_waypoint.symbol
          )

          {:ok, _ledger} =
            Finance.supply_construction_site(
              ship.agent.symbol,
              trade_symbol,
              DateTime.utc_now(),
              units
            )

          {:success, state}

        err ->
          Logger.error("Failed to supply construction site: #{inspect(err)}")
          {:failure, state}
      end
    end)
  end
end
