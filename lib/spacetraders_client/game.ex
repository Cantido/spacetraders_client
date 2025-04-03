defmodule SpacetradersClient.Game do
  alias Phoenix.PubSub
  alias SpacetradersClient.ShipTask
  alias SpacetradersClient.Finance
  alias SpacetradersClient.Game.Agent
  alias SpacetradersClient.Game.Item
  alias SpacetradersClient.Game.Extraction
  alias SpacetradersClient.Game.Ship
  alias SpacetradersClient.Game.ShipCargoItem
  alias SpacetradersClient.Game.ShipyardShip
  alias SpacetradersClient.Game.MarketTradeGood
  alias SpacetradersClient.Game.Shipyard
  alias SpacetradersClient.Game.ShipLoadWorker
  alias SpacetradersClient.Game.System
  alias SpacetradersClient.Game.Waypoint
  alias SpacetradersClient.Game.Market
  alias SpacetradersClient.Systems
  alias SpacetradersClient.Agents
  alias SpacetradersClient.Fleet
  alias SpacetradersClient.Repo

  import Ecto.Query

  require Logger

  @pubsub SpacetradersClient.PubSub

  def load_waypoints!(client, system_symbol, load_events_topic \\ nil) do
    if load_events_topic do
      PubSub.broadcast!(
        @pubsub,
        load_events_topic,
        {
          :data_loading_progress,
          :system_waypoints,
          system_symbol,
          0,
          0
        }
      )
    end

    system = Repo.get_by(System, symbol: system_symbol)

    waypoints_data =
      Stream.iterate(1, &(&1 + 1))
      |> Stream.map(fn page ->
        Systems.list_waypoints(client, system_symbol, page: page)
      end)
      |> Stream.map(fn page ->
        {:ok, %{body: body, status: 200}} = page

        body
      end)
      |> Enum.reduce_while([], fn page, waypoints ->
        acc_waypoints = page["data"] ++ waypoints

        if load_events_topic do
          PubSub.broadcast!(
            @pubsub,
            load_events_topic,
            {
              :data_loading_progress,
              :system_waypoints,
              system_symbol,
              Enum.count(acc_waypoints),
              page["meta"]["total"]
            }
          )
        end

        if Enum.count(acc_waypoints) < page["meta"]["total"] do
          {:cont, acc_waypoints}
        else
          {:halt, acc_waypoints}
        end
      end)

    waypoints =
      Enum.map(waypoints_data, fn waypoint_data ->
        if waypoint = Repo.get_by(Waypoint, symbol: waypoint_data["symbol"]) do
          Repo.preload(waypoint, [:modifiers, :traits])
        else
          Ecto.build_assoc(system, :waypoints)
        end
        |> Waypoint.changeset(waypoint_data)
        |> Repo.insert_or_update!()
      end)

    Enum.each(waypoints_data, fn waypoint_data ->
      if waypoint_data["orbits"] do
        orbited = Repo.get_by!(Waypoint, symbol: waypoint_data["orbits"])

        from(w in Waypoint, where: [symbol: ^waypoint_data["symbol"]])
        |> Repo.update_all(set: [orbits_waypoint_id: orbited.id])
      end
    end)

    waypoints
  end

  def load_ship!(client, ship_symbol) do
    {:ok, %{body: ship_body, status: 200}} = Fleet.get_ship(client, ship_symbol)
    {:ok, %{status: 200, body: agent_body}} = Agents.my_agent(client)

    ship =
      save_ship!(agent_body["data"]["symbol"], ship_body["data"])
      |> Repo.preload(:agent)

    PubSub.broadcast!(
      @pubsub,
      "agent:" <> ship.agent.symbol,
      {:ship_updated, ship.symbol}
    )

    ship
  end

  def save_ship!(agent_symbol, ship_data) do
    agent = Repo.get_by!(Agent, symbol: agent_symbol)

    if ship = Repo.get_by(Ship, symbol: ship_data["symbol"]) do
      ship
      |> Repo.preload([
        :cargo_items,
        :nav_waypoint,
        :nav_route_origin_waypoint,
        :nav_route_destination_waypoint
      ])
      |> Ship.changeset(ship_data)
      |> Repo.update!()
    else
      nav_waypoint =
        Repo.get_by!(Waypoint, symbol: ship_data["nav"]["waypointSymbol"])

      nav_dest =
        Repo.get_by!(Waypoint, symbol: ship_data["nav"]["route"]["destination"]["symbol"])

      nav_orig =
        Repo.get_by!(Waypoint, symbol: ship_data["nav"]["route"]["origin"]["symbol"])

      Ecto.build_assoc(agent, :ships,
        nav_waypoint: nav_waypoint,
        nav_route_destination_waypoint: nav_dest,
        nav_route_origin_waypoint: nav_orig
      )
      |> Ship.changeset(ship_data)
      |> Repo.insert!()
    end

    save_ship_nav!(ship_data["symbol"], ship_data["nav"])
    save_ship_cargo!(ship_data["symbol"], ship_data["cargo"])
  end

  def save_ship_nav!(ship_symbol, ship_nav_data) do
    ship =
      Repo.get_by!(Ship, symbol: ship_symbol)
      |> Repo.preload([
        :nav_waypoint,
        :nav_route_destination_waypoint,
        :nav_route_origin_waypoint
      ])

    nav_waypoint =
      Repo.get_by!(Waypoint, symbol: ship_nav_data["waypointSymbol"])

    nav_dest =
      Repo.get_by!(Waypoint, symbol: ship_nav_data["route"]["destination"]["symbol"])

    nav_orig =
      Repo.get_by!(Waypoint, symbol: ship_nav_data["route"]["origin"]["symbol"])

    ship
    |> Ship.nav_changeset(ship_nav_data)
    |> Ecto.Changeset.put_change(:nav_waypoint_id, nav_waypoint.id)
    |> Ecto.Changeset.put_change(:nav_route_destination_waypoint_id, nav_dest.id)
    |> Ecto.Changeset.put_change(:nav_route_origin_waypoint_id, nav_orig.id)
    |> Repo.update!()
  end

  def save_ship_cargo!(ship_symbol, ship_cargo_data) do
    ship = Repo.get_by!(Ship, symbol: ship_symbol)

    Enum.map(ship_cargo_data["inventory"], fn item_data ->
      item =
        if item = Repo.get_by(Item, symbol: item_data["symbol"]) do
          item
        else
          %Item{
            symbol: item_data["symbol"],
            name: item_data["name"],
            description: item_data["description"]
          }
          |> Repo.insert!()
        end

      if cargo_item = Repo.get_by(ShipCargoItem, ship_id: ship.id, item_id: item.id) do
        cargo_item
        |> Ecto.Changeset.change(%{units: item_data["units"]})
        |> Repo.update!()
      else
        Ecto.build_assoc(ship, :cargo_items)
        |> Ecto.Changeset.change(%{
          item: item,
          units: item_data["units"]
        })
        |> Repo.insert!()
      end
    end)
    |> Enum.map(fn c -> c.id end)
    |> then(fn current_cargo_ids ->
      from(sci in ShipCargoItem,
        join: s in assoc(sci, :ship),
        where: s.id == ^ship.id,
        where: sci.id not in ^current_cargo_ids
      )
      |> Repo.delete_all()
    end)

    ship
  end

  def save_ship_fuel!(ship_symbol, fuel_data) do
    Repo.get_by!(Ship, symbol: ship_symbol)
    |> Ship.fuel_changeset(fuel_data)
    |> Repo.update!()
  end

  def save_ship_cooldown!(ship_symbol, cooldown_data) do
    Repo.get_by!(Ship, symbol: ship_symbol)
    |> Ship.cooldown_changeset(cooldown_data)
    |> Repo.update!()
  end

  def save_extraction!(waypoint_symbol, extraction_data) do
    ship = Repo.get_by!(Ship, symbol: extraction_data["shipSymbol"])
    waypoint = Repo.get_by!(Waypoint, symbol: waypoint_symbol)

    item =
      if item = Repo.get_by(Item, symbol: extraction_data["yield"]["symbol"]) do
        item
      else
        %Item{
          symbol: extraction_data["yield"]["symbol"]
        }
        |> Repo.insert!()
      end

    %Extraction{
      ship_id: ship.id,
      item_id: item.id,
      waypoint_id: waypoint.id,
      units: extraction_data["yield"]["units"]
    }
    |> Ecto.Changeset.change()
    |> Repo.insert!()
  end

  def load_construction_site!(_client, _system_symbol, _waypoint_symbol, _topic \\ nil) do
    # TODO
  end

  def load_shipyard!(client, system_symbol, waypoint_symbol, load_events_topic \\ nil) do
    if load_events_topic do
      PubSub.broadcast!(
        @pubsub,
        load_events_topic,
        {:data_loading, :shipyard, waypoint_symbol}
      )
    end

    {:ok, %{body: body, status: 200}} =
      Systems.get_shipyard(client, system_symbol, waypoint_symbol)

    if shipyard = Repo.get_by(Shipyard, symbol: waypoint_symbol) do
      shipyard
    else
      %Shipyard{symbol: waypoint_symbol}
    end
    |> Repo.preload(:ships)
    |> Shipyard.changeset(body["data"])
    |> Repo.insert_or_update!()

    if load_events_topic do
      PubSub.broadcast!(
        @pubsub,
        load_events_topic,
        {:data_loaded, :shipyard, waypoint_symbol}
      )
    end
  end

  def load_market!(client, system_symbol, waypoint_symbol, load_events_topic \\ nil) do
    if load_events_topic do
      PubSub.broadcast!(
        @pubsub,
        load_events_topic,
        {:data_loading, :market, waypoint_symbol}
      )
    end

    {:ok, %{body: body, status: 200}} =
      Systems.get_market(client, system_symbol, waypoint_symbol)

    market =
      if market = Repo.get_by(Market, symbol: waypoint_symbol) do
        market
      else
        %Market{symbol: waypoint_symbol}
        |> Repo.insert!()
      end
      |> Repo.preload(items: [:item])

    import_data = Enum.map(body["data"]["imports"], &Map.put(&1, "type", :import))
    export_data = Enum.map(body["data"]["exports"], &Map.put(&1, "type", :export))
    exchange_data = Enum.map(body["data"]["exchange"], &Map.put(&1, "type", :exchange))

    current_market_item_ids =
      (import_data ++ export_data ++ exchange_data)
      |> Enum.map(fn e ->
        item =
          if item = Repo.get_by(Item, symbol: e["symbol"]) do
            item
          else
            %Item{}
            |> Item.changeset(e)
            |> Repo.insert!()
          end

        existing_market_item =
          Repo.get_by(MarketTradeGood,
            market_id: market.id,
            item_id: item.id
          )

        market_item =
          if existing_market_item do
            existing_market_item
          else
            Ecto.build_assoc(market, :items, item: item, type: e["type"])
            |> Repo.insert!()
          end
          |> Repo.preload(:item)

        symbol = market_item.item.symbol

        trade_goods =
          Map.fetch!(body, "data")
          |> Map.get("tradeGoods", [])

        if trade_good = Enum.find(trade_goods, fn tg -> tg["symbol"] == symbol end) do
          market_item
          |> MarketTradeGood.changeset(%{
            purchase_price: trade_good["purchasePrice"],
            sell_price: trade_good["sellPrice"],
            trade_volume: trade_good["tradeVolume"],
            supply: trade_good["supply"],
            activity: trade_good["activity"]
          })
          |> Repo.update!()
        else
          market_item
        end
      end)
      |> Enum.map(fn market_item -> market_item.item_id end)

    from(
      mtg in MarketTradeGood,
      where: mtg.market_id == ^market.id,
      where: mtg.item_id not in ^current_market_item_ids
    )
    |> Repo.delete_all()

    if load_events_topic do
      PubSub.broadcast!(
        @pubsub,
        load_events_topic,
        {:data_loaded, :market, waypoint_symbol}
      )
    end

    market
  end

  def load_ship_cargo!(_ship_symbol) do
    # TODO
  end

  @doc """
  Refuel a ship.

  By default, fills a ship's fuel tank to its capacity.

  If `:min_fuel` is a number, then this function will calculate the amount of fuel to buy with the goal of filling your tank in between two goal posts:
    - `min_fuel + emergency_fuel` at the minimum end
    - `ship.fuel_capacity - room_on_top` as a "soft cap," ignored if the minimum ends up being higher.

  Since a "market unit" of fuel equals 100 fuel units, leaving at least 100 units of room means you won't waste fuel filling your tank past its capacity.

  ## Options

    - `:min_fuel` - the minimum amount of fuel you want in your tank after refueling. Default: :maximum, which fills your tank completely
    - `:emergency_fuel` - an amount of fuel beyond the minimum to have after refueling. Default: 100
    - `:room_on_top` - how much fuel capacity to leave empty. Default: 100
  """
  def refuel_ship(client, ship_symbol, opts \\ []) do
    ship =
      Repo.get_by(Ship, symbol: ship_symbol)
      |> Repo.preload(:agent)

    min_fuel_opt = Keyword.get(opts, :min_fuel, :maximum)

    min_fuel =
      if min_fuel_opt == :maximum do
        ship.fuel_capacity
      else
        emergency_fuel = Keyword.get(opts, :emergency_fuel, 100)
        room_on_top = Keyword.get(opts, :room_on_top, 100)

        (min_fuel_opt + emergency_fuel)
        |> max(ship.fuel_capacity - room_on_top)
      end
      |> min(ship.fuel_capacity)

    # One fuel unit you buy on the market
    # fills up 100 fuel units in your ship

    fuel_units_needed =
      max(0, min_fuel - ship.fuel_current)

    market_units_to_buy =
      Float.ceil(fuel_units_needed / 100)

    fuel_units_to_buy = trunc(market_units_to_buy * 100)

    if fuel_units_to_buy > 0 do
      case Fleet.refuel_ship(client, ship_symbol, units: fuel_units_to_buy) do
        {:ok, %{status: 200, body: body}} ->
          agent =
            ship.agent
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
                "#{tx["type"]} #{tx["tradeSymbol"]} × #{tx["units"]} @ #{tx["pricePerUnit"]}/u — #{ship.symbol} @ #{ship.nav_waypoint.symbol}",
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
            {:ship_updated, ship_symbol, ship}
          )

          {:ok, ship}

        err ->
          Logger.error("Failed to refuel ship: #{inspect(err)}")
          {:error, err}
      end
    else
      {:ok, ship}
    end
  end

  def navigate_ship(client, ship_symbol, waypoint_symbol) do
    case Fleet.navigate_ship(client, ship_symbol, waypoint_symbol) do
      {:ok, %{status: 200, body: body}} ->
        save_ship_nav!(ship_symbol, body["data"]["nav"])

        ship =
          save_ship_fuel!(ship_symbol, body["data"]["fuel"])
          |> Repo.preload(:agent)

        %{
          token: ship.agent.token,
          ship_symbol: ship.symbol
        }
        |> ShipLoadWorker.new(scheduled_at: ship.nav_route_arrival_at)
        |> Oban.insert!()

        {:ok, ship}

      {:ok, %{status: 400, body: %{"error" => error_data}}} ->
        {:error, error_data}
    end
  end

  def market(market_symbol) do
    Repo.get_by(Market, symbol: market_symbol)
  end

  def markets(system_symbol) do
    Repo.all(
      from m in Market,
        join: w in Waypoint,
        on: w.symbol == m.symbol,
        where: w.system_symbol == ^system_symbol
    )
  end

  @doc """
  Returns the credit value of all ships in the agent's fleet.

  Ship prices are averaged from all known shipyards.
  """
  def fleet_value(agent_symbol) do
    fleet =
      Repo.all(
        from s in Ship,
          join: a in assoc(s, :agent),
          where: a.symbol == ^agent_symbol
      )

    Enum.map(fleet, fn ship ->
      case ship.registration_role do
        "EXCAVATOR" -> "SHIP_MINING_DRONE"
        "TRANSPORT" -> "SHIP_LIGHT_SHUTTLE"
        "SATELLITE" -> "SHIP_PROBE"
        _ -> nil
      end
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.frequencies()
    |> Enum.map(fn {ship_type, count} ->
      price =
        from(s in ShipyardShip, where: [type: ^ship_type])
        |> Repo.aggregate(:avg, :purchase_price)

      {price, count}
    end)
    |> Enum.reject(fn {price, _count} -> is_nil(price) end)
    |> Enum.map(fn {price, count} -> Decimal.mult(price, count) |> Decimal.to_integer() end)
    |> Enum.sum()
  end

  @doc """
  Returns the credit value of all merchandise in the agent's fleet's cargo holds.

  Merchandise prices are averaged over the selling price from all known markets.
  """
  def merchandise_value(agent_symbol) do
    from(sci in ShipCargoItem,
      join: s in assoc(sci, :ship),
      join: a in assoc(s, :agent),
      where: a.symbol == ^agent_symbol
    )
    |> Repo.all()
    |> Repo.preload(:item)
    |> Enum.map(fn cargo_item ->
      price_per_unit =
        average_selling_price(cargo_item.item.symbol) || 0

      %{
        trade_symbol: cargo_item.item.symbol,
        units: cargo_item.units,
        total_cost: Decimal.mult(price_per_unit, cargo_item.units) |> Decimal.to_integer()
      }
    end)
  end

  def distance_between(wp_a, wp_b) do
    Waypoint.distance(
      Repo.get_by(Waypoint, symbol: wp_a),
      Repo.get_by(Waypoint, symbol: wp_b)
    )
  end

  def add_extraction(_waypoint_symbol, _extraction) do
    # update_in(
    #   game,
    #   [Access.key(:extractions), Access.key(waypoint_symbol, [])],
    #   &[extraction | &1]
    # )
    # |> tap(fn game ->
    #   average_extraction_yield(game)
    # end)
  end

  def average_extraction_yield(_waypoint_symbol) do
    # TODO: Factor in laser/siphon strength

    # waypoint_extractions =
    #   game.extractions
    #   |> Map.get(waypoint_symbol, [])

    # extraction_count = Enum.count(waypoint_extractions)

    # waypoint_extractions
    # |> Enum.map(&Map.get(&1, "yield"))
    # |> Enum.reduce(%{}, fn yield, total_yield ->
    #   total_yield
    #   |> Map.put_new(yield["symbol"], 0)
    #   |> Map.update!(yield["symbol"], &(&1 + yield["units"]))
    # end)
    # |> Map.new(fn {symbol, units} ->
    #   avg_units = units / extraction_count

    #   {symbol, avg_units}
    # end)
  end

  def average_extraction_yield do
    # TODO: Factor in laser/siphon strength

    # extractions =
    #   Map.values(game.extractions)
    #   |> List.flatten()

    # extraction_count = Enum.count(extractions)

    # extractions
    # |> Enum.map(&Map.get(&1, "yield"))
    # |> Enum.reduce(%{}, fn yield, total_yield ->
    #   total_yield
    #   |> Map.put_new(yield["symbol"], 0)
    #   |> Map.update!(yield["symbol"], &(&1 + yield["units"]))
    # end)
    # |> Map.new(fn {symbol, units} ->
    #   avg_units = units / extraction_count

    #   {symbol, avg_units}
    # end)
  end

  def average_extraction_value(_waypoint_symbol) do
    0
    # TODO
    # average_extraction_yield(game, waypoint_symbol)
    # |> Enum.map(fn {trade_symbol, units} ->
    #   value = average_selling_price(system_symbol(waypoint_symbol), trade_symbol)

    #   value * units
    # end)
    # |> Enum.sum()
  end

  def add_survey(_survey) do
    # TODO
    # Map.update!(game, :surveys, fn surveys ->
    #   waypoint_symbol = Map.fetch!(survey, "symbol")

    #   surveys
    #   |> Map.put_new(waypoint_symbol, [])
    #   |> Map.update!(waypoint_symbol, fn survey_list ->
    #     [survey | survey_list]
    #   end)
    #   |> Map.new(fn {wp, surveys} ->
    #     surveys =
    #       Enum.filter(surveys, fn survey ->
    #         {:ok, expiration, _} = DateTime.from_iso8601(survey["expiration"])

    #         DateTime.before?(DateTime.utc_now(), expiration)
    #       end)

    #     {wp, surveys}
    #   end)
    # end)
  end

  def delete_survey(_waypoint_symbol, _survey_sig) do
    # TODO
    # Map.update!(game, :surveys, fn surveys ->
    #   surveys
    #   |> Map.put_new(waypoint_symbol, [])
    #   |> Map.update!(waypoint_symbol, fn survey_list ->
    #     Enum.reject(survey_list, fn survey ->
    #       survey["signature"] == survey_sig
    #     end)
    #   end)
    # end)
  end

  def system_symbol(waypoint_symbol) when is_binary(waypoint_symbol) do
    [sector, system, _waypoint] = String.split(waypoint_symbol, "-", parts: 3)

    sector <> "-" <> system
  end

  def sell_price(waypoint_symbol, trade_symbol) do
    Repo.one(
      from(
        mtg in MarketTradeGood,
        join: m in assoc(mtg, :market),
        join: i in assoc(mtg, :item),
        where: m.symbol == ^waypoint_symbol,
        where: i.symbol == ^trade_symbol,
        select: mtg.sell_price
      )
    )
  end

  def purchase_price(waypoint_symbol, trade_symbol) do
    Repo.one(
      from(
        mtg in MarketTradeGood,
        join: m in assoc(mtg, :market),
        join: i in assoc(mtg, :item),
        where: m.symbol == ^waypoint_symbol,
        where: i.symbol == ^trade_symbol,
        select: mtg.purchase_price
      )
    )
  end

  def profit(start_waypoint, end_waypoint, trade_symbol) do
    expense = purchase_price(start_waypoint, trade_symbol)
    income = sell_price(end_waypoint, trade_symbol)

    income - expense
  end

  def selling_markets(system_symbol, trade_symbol) do
    from(
      m in Market,
      join: w in Waypoint,
      on: m.symbol == w.symbol,
      join: s in assoc(w, :system),
      join: mtg in assoc(m, :trade_goods),
      join: i in assoc(mtg, :item),
      where: s.symbol == ^system_symbol,
      where: i.symbol == ^trade_symbol,
      where: not is_nil(mtg.sell_price),
      select: {m, mtg.sell_price}
    )
    |> Repo.all()
  end

  def selling_markets(trade_symbol) do
    from(
      m in Market,
      join: mtg in assoc(m, :trade_goods),
      join: i in assoc(mtg, :item),
      where: i.symbol == ^trade_symbol,
      where: not is_nil(mtg.sell_price),
      select: {m, mtg.sell_price}
    )
    |> Repo.all()
  end

  def average_selling_price(system_symbol, trade_symbol) do
    from(
      mtg in MarketTradeGood,
      join: m in assoc(mtg, :market),
      join: i in assoc(mtg, :item),
      join: w in Waypoint,
      on: m.symbol == w.symbol,
      join: s in assoc(w, :system),
      where: s.symbol == ^system_symbol,
      where: i.symbol == ^trade_symbol
    )
    |> Repo.aggregate(:avg, :sell_price)
  end

  def average_selling_price(trade_symbol) do
    from(
      mtg in MarketTradeGood,
      join: i in assoc(mtg, :item),
      where: i.symbol == ^trade_symbol
    )
    |> Repo.aggregate(:avg, :sell_price)
  end

  def best_selling_market_price(system_symbol, trade_symbol) do
    selling_markets(system_symbol, trade_symbol)
    |> Enum.sort_by(fn {_, price} -> price end, :desc)
    |> List.first()
  end

  def best_selling_market_price(trade_symbol) do
    selling_markets(trade_symbol)
    |> Enum.sort_by(fn {_, price} -> price end, :desc)
    |> List.first()
  end

  def purchase_markets(system_symbol, trade_symbol) do
    from(
      m in Market,
      join: w in Waypoint,
      on: m.symbol == w.symbol,
      join: s in assoc(w, :system),
      join: mtg in assoc(m, :trade_goods),
      join: i in assoc(mtg, :item),
      where: s.symbol == ^system_symbol,
      where: i.symbol == ^trade_symbol,
      where: not is_nil(mtg.purchase_price),
      select: {m, mtg.purchase_price}
    )
    |> Repo.all()
  end

  def purchase_markets(trade_symbol) do
    from(
      m in Market,
      join: mtg in assoc(m, :trade_goods),
      join: i in assoc(mtg, :item),
      where: i.symbol == ^trade_symbol,
      where: not is_nil(mtg.purchase_price),
      select: {m, mtg.purchase_price}
    )
    |> Repo.all()
  end

  def average_purchase_price(system_symbol, trade_symbol) do
    purchase_markets(system_symbol, trade_symbol)
    |> Enum.map(fn {_, price} -> price end)
    |> avg()
  end

  def average_purchase_price(trade_symbol) do
    purchase_markets(trade_symbol)
    |> Enum.map(fn {_, price} -> price end)
    |> avg()
  end

  defp avg(nums, default \\ nil) do
    count = Enum.count(nums)

    if count > 0 do
      Enum.sum(nums) / count
    else
      default
    end
  end

  def best_purchase_market_price(system_symbol, trade_symbol) do
    purchase_markets(system_symbol, trade_symbol)
    |> Enum.sort_by(fn {_, price} -> price end, :asc)
    |> List.first()
  end

  def best_purchase_market_price(trade_symbol) do
    purchase_markets(trade_symbol)
    |> Enum.sort_by(fn {_, price} -> price end, :asc)
    |> List.first()
  end

  def nearest_fuel_waypoint(waypoint_symbol) do
    waypoint = Repo.get_by(Waypoint, symbol: waypoint_symbol)

    from(
      m in Market,
      join: w in Waypoint,
      on: m.symbol == w.symbol,
      join: s in assoc(w, :system),
      join: mtg in assoc(m, :items),
      join: i in assoc(mtg, :item),
      where: i.symbol == "FUEL",
      where: s.symbol == ^waypoint.system_symbol,
      select: w
    )
    |> Repo.all()
    |> Enum.sort_by(
      fn market_waypoint ->
        Waypoint.distance(waypoint, market_waypoint)
      end,
      :asc
    )
    |> List.first()
  end

  def surveys(_waypoint_symbol) do
    # TODO
    # game.surveys
    # |> Map.get(waypoint_symbol, [])
    # |> Enum.filter(fn survey ->
    #   {:ok, expiration, _} = DateTime.from_iso8601(survey["expiration"])

    #   DateTime.before?(DateTime.utc_now(), expiration)
    # end)
  end

  def market_actions do
    markets =
      Repo.all(Market)
      |> Repo.preload(trade_goods: [:item])

    Enum.flat_map(markets, fn start_market ->
      start_market.trade_goods
      |> Enum.filter(fn t -> t.purchase_price > 0 end)
      |> Enum.flat_map(fn start_trade_good ->
        Enum.flat_map(markets, fn end_market ->
          end_market.trade_goods
          |> Enum.filter(fn end_trade_good ->
            start_trade_good.item_id == end_trade_good.item_id &&
              end_trade_good.sell_price > start_trade_good.purchase_price
          end)
          |> Enum.map(fn end_trade_good ->
            start_wp = Repo.get_by(Waypoint, symbol: start_market.symbol)
            end_wp = Repo.get_by(Waypoint, symbol: end_market.symbol)

            ShipTask.new(
              :trade,
              %{
                trade_symbol: start_trade_good.item_symbol,
                start_wp: start_wp.symbol,
                end_wp: end_wp.symbol,
                volume: min(end_trade_good.trade_volume, start_trade_good.trade_volume),
                profit: end_trade_good.sell_price - start_trade_good.purchase_price,
                credits_required: start_trade_good["purchasePrice"],
                revenue: end_trade_good.sell_price,
                roi: end_trade_good.sell_price / start_trade_good.purchase_price,
                distance: Waypoint.distance(start_wp, end_wp)
              }
            )
          end)
        end)
      end)
    end)
  end

  def actions(agent_symbol) do
    resource_extractions =
      from(s in Ship,
        join: nav_wp in assoc(s, :nav_waypoint),
        join: sys in assoc(nav_wp, :system),
        join: wp in assoc(sys, :waypoints),
        select: wp,
        distinct: true
      )
      |> Repo.all()
      |> Enum.flat_map(fn waypoint ->
        resource_actions(waypoint)
      end)

    resource_pickups = resource_pickup_actions(agent_symbol)
    market_actions = market_actions()
    market_vis = market_visibility_actions(agent_symbol)
    construction_actions = construction_actions()

    resource_extractions ++
      resource_pickups ++ market_actions ++ market_vis ++ construction_actions
  end

  defp resource_actions(waypoint) do
    cond do
      waypoint.type in ~w(ASTEROID ASTEROID_FIELD ENGINEERED_ASTEROID) ->
        task =
          ShipTask.new(
            :mine,
            %{waypoint_symbol: waypoint.symbol},
            [
              &Ship.has_mining_laser?/1,
              &Ship.has_cargo_capacity?/1
            ]
          )

        [task]

      waypoint.type in ~w(GAS_GIANT) ->
        task =
          ShipTask.new(
            :siphon_resources,
            %{waypoint_symbol: waypoint.symbol},
            [
              &Ship.has_gas_siphon?/1,
              &Ship.has_cargo_capacity?/1
            ]
          )

        [task]

      true ->
        []
    end
  end

  defp resource_pickup_actions(agent_symbol) do
    # First phase of this pipeline: collecting all excavators and their contents
    # into maps by waypoint, so we can pick up all of one item at once.
    # This will make it easier to find buyers.

    from(s in Ship,
      join: a in assoc(s, :agent),
      where: a.symbol == ^agent_symbol
    )
    |> Repo.all()
    |> Repo.preload(:cargo_items)
    |> Enum.filter(fn ship ->
      ship.registration_role == "EXCAVATOR" &&
        ship.nav_status == :in_orbit
    end)
    |> Enum.group_by(fn ship -> ship.nav_waypoint.symbol end)
    |> Enum.map(fn {waypoint_symbol, ships} ->
      # Example of the data structure I'm trying to build, one for each waypoint:
      #
      # %{
      #   "IRON_ORE" => %{
      #     "COSMIC-ROSE-5" => 5
      #   }
      # }
      resources_available =
        Enum.reduce(ships, %{}, fn ship, resources ->
          Enum.reduce(ship.cargo_items, resources, fn item, resources ->
            resources
            |> Map.put_new(item.item_symbol, %{})
            |> Map.update!(item.item_symbol, fn resource ->
              Map.put(resource, ship.symbol, item.units)
            end)
          end)
        end)

      {waypoint_symbol, resources_available}
    end)

    # Second phase: Turning excavator content groups into pickup tasks

    |> Enum.flat_map(fn {waypoint_symbol, resources_available} ->
      Enum.map(resources_available, fn {trade_symbol, ships_carrying} ->
        ShipTask.new(
          :pickup,
          %{
            start_wp: waypoint_symbol,
            trade_symbol: trade_symbol,
            ship_pickups: ships_carrying
          }
        )
      end)
    end)

    # Multiply the pickup tasks by the material buyers available in the system,
    # adding the buyer market and total profit to the task args.

    |> Enum.flat_map(fn pickup_task ->
      selling_markets(
        system_symbol(pickup_task.args.start_wp),
        pickup_task.args.trade_symbol
      )
      |> Enum.map(fn {market, price} ->
        volume = Enum.find(market.trade_goods, fn t -> t.item_symbol end).trade_volume

        ShipTask.variation(pickup_task, %{
          volume: volume,
          price: price,
          end_wp: market.symbol
        })
      end)
    end)

    # Disallow the mining ships themselves from picking up anything

    |> Enum.map(fn pickup_task ->
      Enum.reduce(pickup_task.args.ship_pickups, pickup_task, fn {ship_symbol, _units},
                                                                 pickup_task ->
        pickup_task
        |> ShipTask.add_condition(fn ship -> ship.symbol != ship_symbol end)
        |> ShipTask.add_condition(fn ship -> ship.registration_role != "EXCAVATOR" end)
      end)
    end)
  end

  defp market_visibility_actions(agent_symbol) do
    fleet =
      from(s in Ship,
        join: a in assoc(s, :agent),
        where: a.symbol == ^agent_symbol,
        preload: :nav_waypoint
      )
      |> Repo.all()

    satellites_at_wp =
      Repo.all(Market)
      |> Enum.map(fn market ->
        market.symbol
      end)
      |> Map.new(fn waypoint_symbol ->
        satellites =
          Enum.filter(fleet, fn ship ->
            ship.nav_waypoint.symbol == waypoint_symbol &&
              ship.registration_role == "SATELLITE"
          end)

        {waypoint_symbol, satellites}
      end)

    duplicate_sat_symbols =
      satellites_at_wp
      |> Enum.flat_map(fn {_waypoint, sats} ->
        Enum.drop(sats, 1)
      end)
      |> Enum.map(fn sat ->
        sat.symbol
      end)

    satellites_at_wp
    |> Map.filter(fn {_wp, satellites} ->
      Enum.count(satellites) == 0
    end)
    |> Enum.map(fn {waypoint_symbol, _sats} ->
      ShipTask.new(
        :goto,
        %{waypoint_symbol: waypoint_symbol},
        [
          fn ship -> ship.symbol in duplicate_sat_symbols end,
          fn ship -> ship.registration_role == "SATELLITE" end
        ]
      )
    end)
  end

  defp construction_actions do
    # game.construction_sites
    # |> Enum.map(fn {_symbol, site} -> site end)
    # |> Enum.reject(fn site -> site["isComplete"] end)
    # |> Enum.flat_map(fn site ->
    #   Enum.map(site["materials"], fn material ->
    #     ShipTask.new(
    #       :deliver_construction_materials,
    #       %{
    #         waypoint_symbol: site["symbol"],
    #         trade_symbol: material["tradeSymbol"],
    #         remaining_units: material["required"] - material["fulfilled"],
    #         required_units: material["required"],
    #         fulfilled_units: material["fulfilled"]
    #       }
    #     )
    #   end)
    #   |> Enum.reject(fn task -> task.args.remaining_units == 0 end)
    # end)
    []
  end
end
