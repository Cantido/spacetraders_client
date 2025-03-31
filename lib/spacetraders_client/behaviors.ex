defmodule SpacetradersClient.Behaviors do
  alias SpacetradersClient.Systems
  alias SpacetradersClient.ShipTask
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

  def for_task(%ShipTask{name: :goto} = task) do
    Node.sequence([
      wait_for_transit(),
      refuel(),
      travel_to_waypoint(task.args.waypoint_symbol, flight_mode: :cruise)
    ])
  end

  def for_task(%ShipTask{name: :selling} = task) do
    Node.sequence([
      wait_for_transit(),
      refuel(min_fuel: task.args.fuel_consumed),
      travel_to_waypoint(task.args.waypoint_symbol, flight_mode: task.args.flight_mode),
      wait_for_transit(),
      dock_ship(),
      sell_cargo_item(task.args.trade_symbol, task.args.units)
    ])
  end

  def for_task(%ShipTask{name: :trade} = task) do
    whole_volume_count = div(task.args.units, task.args.volume)
    units_in_last_volume = rem(task.args.units, task.args.volume)

    whole_volume_amounts =
      Stream.repeatedly(fn -> task.args.volume end)
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
      refuel(min_fuel: task.args.start_fuel_consumed),
      travel_to_waypoint(task.args.start_wp,
        flight_mode: task.args.start_flight_mode,
        fuel_min: task.args.start_fuel_consumed
      ),
      wait_for_transit(),
      dock_ship(),
      Node.sequence(
        Enum.map(volume_amounts_to_trade, fn units ->
          buy_cargo(task.args.trade_symbol, units, max_price: task.args.max_purchase_price)
        end)
      ),
      refuel(min_fuel: task.args.end_fuel_consumed),
      travel_to_waypoint(task.args.end_wp,
        flight_mode: task.args.end_flight_mode,
        fuel_min: task.args.end_fuel_consumed
      ),
      wait_for_transit(),
      dock_ship(),
      sell_cargo_item(task.args.trade_symbol, task.args.units,
        min_price: task.args.min_sell_price
      )
    ])
  end

  def for_task(%ShipTask{name: :pickup} = task) do
    Node.sequence([
      wait_for_transit(),
      refuel(min_fuel: task.args.fuel_consumed),
      travel_to_waypoint(task.args.start_wp, flight_mode: task.args.start_flight_mode),
      wait_for_transit(),
      Node.sequence(
        Enum.map(task.args.ship_pickups, fn {pickup_ship_symbol, units} ->
          pickup_cargo(pickup_ship_symbol, task.args.trade_symbol, units)
        end)
      )
    ])
  end

  def for_task(%ShipTask{name: :deliver_construction_materials} = task) do
    if task.args.direct_delivery? do
      Node.sequence([
        refuel(min_fuel: task.args.ship_to_site_fuel_consumed),
        travel_to_waypoint(task.args.waypoint_symbol),
        wait_for_transit(),
        dock_ship(),
        deliver_construction_materials(task.args.trade_symbol, task.args.units)
      ])
    else
      Node.sequence([
        wait_for_transit(),
        refuel(min_fuel: task.args.ship_to_market_fuel_consumed),
        travel_to_waypoint(task.args.market_waypoint),
        wait_for_transit(),
        dock_ship(),
        buy_cargo(task.args.trade_symbol, task.args.units),
        refuel(min_fuel: task.args.market_to_site_fuel_consumed),
        travel_to_waypoint(task.args.waypoint_symbol),
        wait_for_transit(),
        dock_ship(),
        deliver_construction_materials(task.args.trade_symbol, task.args.units)
      ])
    end
  end

  def for_task(%ShipTask{name: :mine} = task) do
    Node.sequence([
      refuel(min_fuel: task.args.fuel_consumed),
      travel_to_waypoint(task.args.waypoint_symbol, flight_mode: :cruise),
      wait_for_transit(),
      wait_for_ship_cooldown(),
      extract_resources()
    ])
  end

  def for_task(%ShipTask{name: :siphon_resources} = task) do
    Node.sequence([
      refuel(min_fuel: task.args.fuel_consumed),
      travel_to_waypoint(task.args.waypoint_symbol, flight_mode: :cruise),
      wait_for_transit(),
      wait_for_ship_cooldown(),
      siphon_resources()
    ])
  end

  def for_task(%ShipTask{name: :idle}) do
    Node.action(fn _ -> :success end)
  end

  def enter_orbit(ship_symbol) do
    Node.select([
      Node.condition(fn _state ->
        ship = Repo.get(Ship, ship_symbol)

        ship.nav_status == :in_orbit
      end),
      Node.action(fn state ->
        case Fleet.orbit_ship(state.client, ship_symbol) do
          {:ok, %{status: 200, body: body}} ->
            ship =
              Repo.get(Ship, ship_symbol)
              |> Ship.changeset(body["data"])
              |> Repo.update!()

            PubSub.broadcast(
              @pubsub,
              "agent:#{ship.agent_symbol}",
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
          ship = Repo.get(Ship, state.ship_symbol)

          ship.nav_status == :in_transit
        end)
      ),
      Node.select([
        Node.condition(fn state ->
          ship = Repo.get(Ship, state.ship_symbol)

          ship.nav_status == :in_orbit
        end),
        Node.action(fn state ->
          case Fleet.orbit_ship(state.client, state.ship_symbol) do
            {:ok, %{status: 200, body: body}} ->
              ship =
                Repo.get(Ship, state.ship_symbol)
                |> Ship.nav_changeset(body["data"]["nav"])
                |> Repo.update!()

              PubSub.broadcast(
                @pubsub,
                "agent:#{ship.agent_symbol}",
                {:ship_updated, state.ship_symbol, ship}
              )

              {:success, state}

            {:ok, %{status: 400, body: %{"error" => %{"code" => 4214, "data" => data}}}} ->
              ship =
                Repo.get(Ship, state.ship_symbol)
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
        ship = Repo.get(Ship, state.ship_symbol)

        ship.nav_status == :docked
      end),
      Node.action(fn state ->
        case Fleet.dock_ship(state.client, state.ship_symbol) do
          {:ok, %{status: 200, body: body}} ->
            ship =
              Repo.get(Ship, state.ship_symbol)
              |> Ship.nav_changeset(body["data"]["nav"])
              |> Repo.update!()

            PubSub.broadcast(
              @pubsub,
              "agent:#{ship.agent_symbol}",
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
            Repo.get(Ship, state.ship_symbol)
            |> Ship.nav_changeset(body["data"]["nav"])
            |> Repo.update!()

          PubSub.broadcast(
            @pubsub,
            "agent:#{ship.agent_symbol}",
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
        ship = Repo.get(Ship, state.ship_symbol)

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
          ship = Repo.get(Ship, state.ship_symbol)
          ship.fuel_current >= state.min_fuel
        end),
        Node.sequence([
          travel_to_nearest_fuel(),
          wait_for_transit(),
          dock_ship(),
          Node.action(fn state ->
            ship = Repo.get(Ship, state.ship_symbol)

            fallback_min_fuel = ship.fuel_capacity - 100

            fuel_units_needed =
              max(0, Map.get(state, :min_fuel, fallback_min_fuel) - ship.fuel_current)

            market_units_to_buy =
              Float.ceil(fuel_units_needed / 100)

            fuel_units_to_buy = trunc(market_units_to_buy * 100)

            if fuel_units_to_buy > 0 do
              case Fleet.refuel_ship(state.client, state.ship_symbol, units: fuel_units_to_buy) do
                {:ok, %{status: 200, body: body}} ->
                  agent =
                    Repo.get(Agent, ship.agent_symbol)
                    |> Agent.changeset(body["data"]["agent"])
                    |> Repo.update!()

                  ship =
                    ship
                    |> Ship.fuel_changeset(body["data"]["fuel"])
                    |> Repo.update!()

                  tx = body["data"]["transaction"]
                  {:ok, ts, _} = DateTime.from_iso8601(tx["timestamp"])

                  if tx["units"] > 0 do
                    {:ok, _ledger} =
                      Finance.post_journal(
                        agent.symbol,
                        ts,
                        "#{tx["type"]} #{tx["tradeSymbol"]} × #{tx["units"]} @ #{tx["pricePerUnit"]}/u — #{state.ship_symbol} @ #{ship.nav_waypoint_symbol}",
                        "Fuel",
                        "Cash",
                        tx["totalPrice"]
                      )
                  end

                  PubSub.broadcast(
                    @pubsub,
                    "agent:#{agent.symbol}",
                    {:agent_updated, agent}
                  )

                  PubSub.broadcast(
                    @pubsub,
                    "agent:#{agent.symbol}",
                    {:ship_updated, state.ship_symbol, ship}
                  )

                  {:success, state}

                err ->
                  Logger.error("Failed to refuel ship: #{inspect(err)}")
                  {:failure, state}
              end
            else
              :success
            end
          end)
        ])
      ])
    ])
  end

  def travel_to_nearest_fuel do
    Node.sequence([
      fetch_fuel_markets(),
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

  def fetch_fuel_markets do
    Node.action(fn state ->
      ship = Repo.get(Ship, state.ship_symbol) |> Repo.preload(:nav_waypoint)

      fuel_markets =
        Game.purchase_markets(ship.nav_waypoint.system_symbol, "FUEL")
        |> Enum.sort_by(fn {market, _price} ->
          Game.distance_between(ship.nav_waypoint_symbol, market.symbol)
        end)

      {:success, Map.put(state, :fuel_markets, fuel_markets)}
    end)
  end

  def at_fuel_market? do
    Node.condition(fn state ->
      ship = Repo.get(Ship, state.ship_symbol) |> Repo.preload(:nav_waypoint)

      Enum.any?(Map.get(state, :fuel_markets, []), fn {market, _price} ->
        market.symbol == ship.nav_waypoint_symbol
      end)
    end)
  end

  def navigate_ship_to_fuel_market do
    Node.action(fn state ->
      {fuel_wp, _price} =
        Map.get(state, :fuel_markets, [])
        |> List.first()

      case Fleet.navigate_ship(state.client, state.ship_symbol, fuel_wp.symbol) do
        {:ok, %{status: 200, body: body}} ->
          ship =
            Repo.get(Ship, state.ship_symbol)
            |> Ship.nav_changeset(body["data"]["nav"])
            |> Repo.update!()

          PubSub.broadcast(
            @pubsub,
            "agent:#{ship.agent_symbol}",
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
  end

  def wait_for_transit do
    Node.action(fn state ->
      ship = Repo.get(Ship, state.ship_symbol)
      arrival = ship.nav_route_arrival_at

      if arrival && ship.nav_status == :in_transit do
        if DateTime.before?(DateTime.utc_now(), arrival) do
          :running
        else
          {:ok, %{status: 200, body: body}} =
            Fleet.get_ship_nav(state.client, state.ship_symbol)

          ship =
            ship
            |> Ship.nav_changeset(body["data"])
            |> Repo.update!()

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
      ship = Repo.get(Ship, state.ship_symbol)

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
        ship = Repo.get(Ship, state.ship_symbol)

        case Fleet.siphon_resources(state.client, state.ship_symbol) do
          {:ok, %{status: 201, body: body}} ->
            ship =
              ship
              |> Ship.changeset(body["data"])
              |> Repo.update!()
              |> Repo.preload(:nav_waypoint)

            # TODO
            # |> Game.add_extraction(ship["nav"]["waypointSymbol"], body["data"]["siphon"])

            yield_symbol = get_in(body, ~w(data siphon yield symbol))
            yield_units = get_in(body, ~w(data siphon yield units))

            price =
              Game.average_purchase_price(ship.nav_waypoint.system_symbol, yield_symbol)

            value_of_material = trunc(price * yield_units)

            {:ok, _ledger} =
              Finance.post_journal(
                ship.agent_symbol,
                DateTime.utc_now(),
                "Extraction of #{yield_units} × #{yield_symbol} — #{state.ship_symbol} @ #{ship.nav_waypoint_symbol}",
                "Merchandise",
                "Natural Resources",
                value_of_material
              )

            {:ok, _ledger} =
              Finance.purchase_inventory_by_total(
                ship.agent_symbol,
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

          err ->
            Logger.error("Failed to extract resources: #{inspect(err)}")
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
        ship = Repo.get(Ship, state.ship_symbol) |> Repo.preload(:nav_waypoint)

        best_survey =
          Game.surveys(ship.nav_waypoint_symbol)
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
            ship =
              ship
              |> Ship.changeset(body["data"])
              |> Repo.update!()

            # TODO
            # |> Game.add_extraction(ship["nav"]["waypointSymbol"], body["data"]["extraction"])

            yield_symbol = get_in(body, ~w(data extraction yield symbol))
            yield_units = get_in(body, ~w(data extraction yield units))

            price =
              Game.average_selling_price(ship.nav_waypoint.sytem_symbol, yield_symbol)

            value_of_material = trunc(price * yield_units)

            {:ok, _ledger} =
              Finance.post_journal(
                ship.agent_symbol,
                DateTime.utc_now(),
                "Extraction of #{yield_units} × #{yield_symbol} — #{state.ship_symbol} @ #{ship.nav_waypoint_symbol}",
                "Merchandise",
                "Natural Resources",
                value_of_material
              )

            {:ok, _ledger} =
              Finance.purchase_inventory_by_total(
                ship.agent_symbol,
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
                ship.nav_waypoint_symbol,
                best_survey["signature"]
              )

            {:failure, Map.put(state, :game, game)}

          err ->
            Logger.error("Failed to extract resources: #{inspect(err)}")
            {:failure, state}
        end
      end)
    ])
  end

  def cargo_full do
    Node.condition(fn state ->
      ship = Repo.get(Ship, state.ship_symbol) |> Repo.preload(:cargo_items)

      Ship.cargo_current(ship) == ship.cargo_capacity
    end)
  end

  def cargo_empty do
    Node.condition(fn state ->
      ship = Repo.get(Ship, state.ship_symbol) |> Repo.preload(:cargo_items)

      Ship.cargo_current(ship) == 0
    end)
  end

  def jettison_cargo do
    Node.select([
      cargo_empty(),
      Node.sequence([
        enter_orbit(),
        Node.action(fn state ->
          ship = Repo.get(Ship, state.ship_symbol) |> Repo.preload([:cargo_items, :nav_waypoint])

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
                  ship
                  |> Ship.cargo_changeset(body["data"]["cargo"])
                  |> Repo.update!()

                PubSub.broadcast(
                  @pubsub,
                  "agent:#{ship.agent_symbol}",
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
        ship = Repo.get(Ship, state.ship_symbol)

        ship.nav_waypoint_symbol == waypoint_symbol
      end),
      Node.sequence([
        enter_orbit(),
        Node.action(fn state ->
          case Fleet.set_flight_mode(state.client, state.ship_symbol, flight_mode) do
            {:ok, %{status: 200, body: body}} ->
              ship =
                Repo.get(Ship, state.ship_symbol)
                |> Ship.nav_changeset(body["data"])
                |> Repo.update!()

              PubSub.broadcast(
                @pubsub,
                "agent:#{ship.agent_symbol}",
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
              ship =
                Repo.get(Ship, state.ship_symbol)
                |> Ship.nav_changeset(body["data"]["nav"])
                |> Ship.fuel_changeset(body["data"]["fuel"])
                |> Repo.update!()

              PubSub.broadcast(
                @pubsub,
                "agent:#{ship.agent_symbol}",
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
        ship = Repo.get(Ship, state.ship_symbol)

        market = Repo.get(Market, ship.nav_waypoint_symbol) |> Repo.preload(:trade_goods)

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
        ship = Repo.get(Ship, state.ship_symbol) |> Repo.preload(:cargo_items)

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
                  Repo.get(Ship, state.ship_symbol)
                  |> Ship.cargo_changeset(body["data"]["cargo"])
                  |> Repo.update!()

                agent =
                  Repo.get(Agent, ship.agent_symbol)
                  |> Agent.changeset(body["data"]["agent"])
                  |> Repo.update!()

                # TODO: reload market

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
              Repo.get(Ship, source_ship_symbol)
              |> Ship.cargo_changeset(body["data"]["cargo"])
              |> Repo.update!()

            Game.load_ship_cargo!(state.ship_symbol)

            receiving_ship = Repo.get(Ship, state.ship_symbol)

            PubSub.broadcast(
              @pubsub,
              "agent:#{source_ship.agent_symbol}",
              {:ship_updated, source_ship.symbol, source_ship}
            )

            PubSub.broadcast(
              @pubsub,
              "agent:#{receiving_ship.agent_symbol}",
              {:ship_updated, receiving_ship.symbol, receiving_ship}
            )

            {:success, state}

          {:ok, %{status: 400, body: %{"error" => %{"code" => 4234, "data" => data}}}} ->
            source_ship =
              Repo.get(Ship, data["shipSymbol"])
              |> Ecto.Changeset.change(%{nav_waypoint_symbol: data["destinationSymbol"]})
              |> Repo.update!()

            receiving_ship =
              Repo.get(Ship, data["targetShipSymbol"])
              |> Ecto.Changeset.change(%{
                nav_waypoint_symbol: data["conflictingDestinationSymbol"]
              })
              |> Repo.update!()

            PubSub.broadcast(
              @pubsub,
              "agent:#{source_ship.agent_symbol}",
              {:ship_updated, source_ship.symbol, source_ship}
            )

            PubSub.broadcast(
              @pubsub,
              "agent:#{receiving_ship.agent_symbol}",
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
              Repo.get(Ship, state.ship_symbol)
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
              Repo.get(Ship, state.ship_symbol)
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
          ship = Repo.get(Ship, state.ship_symbol)

          market = Game.market(ship.nav_waypoint_symbol) |> Repo.preload(:trade_goods)

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
              Repo.get(Ship, state.ship_symbol)
              |> Repo.preload(:cargo_items)
              |> Ship.cargo_changeset(body["data"]["cargo"])
              |> Repo.update!()

            agent =
              Repo.get(Agent, ship.agent_symbol)
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
                "#{tx["type"]} #{tx["tradeSymbol"]} × #{tx["units"]} @ #{tx["pricePerUnit"]}/u — #{state.ship_symbol} @ #{ship.nav_waypoint_symbol}",
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
              "agent:#{ship.agent_symbol}",
              {:ship_updated, state.ship_symbol, ship}
            )

            {:success, state}

          err ->
            Logger.error("Failed to purchase cargo: #{inspect(err)}")
            {:failure, state}
        end
      end),
      Node.action(fn state ->
        ship = Repo.get(Ship, state.ship_symbol) |> Repo.preload(:nav_waypoint)

        Game.load_market!(state.client, ship.nav_waypoint.system_symbol, ship.nav_waypoint_symbol)

        {:success, state}
      end)
    ])
  end

  def deliver_construction_materials(trade_symbol, units) do
    Node.action(fn state ->
      ship =
        Repo.get(Ship, state.ship_symbol)
        |> Repo.preload(:nav_waypoint)

      case Systems.supply_construction_site(
             state.client,
             ship.nav_waypoint.system_symbol,
             ship.nav_waypoint_symbol,
             state.ship_symbol,
             trade_symbol,
             units
           ) do
        {:ok, %{status: 201, body: body}} ->
          ship =
            ship
            |> Ship.cargo_changeset(body["data"]["cargo"])
            |> Repo.update!()

          Game.load_construction_site!(
            state.client,
            ship.nav_waypoint.system_symbol,
            ship.nav_waypoint_symbol
          )

          {:ok, _ledger} =
            Finance.supply_construction_site(
              ship.agent_symbol,
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
