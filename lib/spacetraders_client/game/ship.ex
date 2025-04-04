defmodule SpacetradersClient.Game.Ship do
  use Ecto.Schema
  use Timex

  alias SpacetradersClient.Game.Agent
  alias SpacetradersClient.Game.Waypoint
  alias SpacetradersClient.Game.ShipCargoItem
  alias SpacetradersClient.Game.Item

  import Ecto.Changeset

  schema "ships" do
    field :symbol, :string
    belongs_to :agent, Agent

    belongs_to :nav_waypoint, Waypoint

    field :registration_role, :string

    belongs_to :nav_route_destination_waypoint, Waypoint

    belongs_to :nav_route_origin_waypoint, Waypoint

    field :nav_route_departure_at, :utc_datetime_usec
    field :nav_route_arrival_at, :utc_datetime_usec

    field :nav_status, Ecto.Enum,
      values: [in_transit: "IN_TRANSIT", in_orbit: "IN_ORBIT", docked: "DOCKED"]

    field :nav_flight_mode, Ecto.Enum,
      values: [drift: "DRIFT", stealth: "STEALTH", cruise: "CRUISE", burn: "BURN"]

    field :cooldown_total_seconds, :integer
    field :cooldown_expires_at, :utc_datetime_usec

    field :cargo_capacity, :integer

    has_many :cargo_items, ShipCargoItem, on_replace: :delete_if_exists

    field :fuel_capacity, :integer
    field :fuel_current, :integer

    timestamps(type: :utc_datetime_usec)
  end

  @required_params [
    :symbol,
    :registration_role,
    :nav_route_departure_at,
    :nav_route_arrival_at,
    :nav_status,
    :nav_flight_mode,
    :cooldown_total_seconds,
    :cargo_capacity,
    :fuel_capacity,
    :fuel_current
  ]

  @optional_params [
    :cooldown_expires_at
  ]

  @allowed_params @required_params ++ @optional_params

  def changeset(model, params) do
    params = %{
      symbol: params["symbol"],
      registration_role: params["registration"]["role"],
      nav_route_departure_at: params["nav"]["route"]["departureTime"],
      nav_route_arrival_at: params["nav"]["route"]["arrival"],
      nav_status: params["nav"]["status"],
      nav_flight_mode: params["nav"]["flightMode"],
      cooldown_total_seconds: params["cooldown"]["totalSeconds"],
      cooldown_expires_at: params["cooldown"]["expiration"],
      cargo_capacity: params["cargo"]["capacity"],
      fuel_capacity: params["fuel"]["capacity"],
      fuel_current: params["fuel"]["current"]
    }

    model
    |> cast(params, @allowed_params)
    |> cargo_changeset(params["cargo"])
    |> validate_required(@required_params)
    |> assoc_constraint(:agent)
  end

  def nav_changeset(model, params) do
    params = %{
      nav_route_departure_at: params["route"]["departureTime"],
      nav_route_arrival_at: params["route"]["arrival"],
      nav_status: params["status"],
      nav_flight_mode: params["flightMode"]
    }

    model
    |> cast(params, @allowed_params)
    |> validate_required(@required_params)
  end

  def cargo_changeset(model, nil), do: change(model, %{})

  def cargo_changeset(model, params) do
    cargo_items_params =
      Map.get(params, "inventory", [])
      |> Enum.map(fn item ->
        item_params = Map.take(item, ~w(symbol name description))

        %{
          "item" => item_params,
          "units" => item["units"]
        }
      end)

    params = %{
      "cargo_items" => cargo_items_params
    }

    model
    |> cast(params, [])
    |> cast_assoc(:cargo_items)
  end

  def cooldown_changeset(model, params) do
    params = %{
      cooldown_total_seconds: params["totalSeconds"],
      cooldown_expires_at: params["expiration"]
    }

    model
    |> cast(params, [:cooldown_total_seconds, :cooldown_expires_at])
    |> validate_required(@required_params)
    |> assoc_constraint(:agent)
  end

  def fuel_changeset(model, params) do
    params = %{
      fuel_capacity: params["capacity"],
      fuel_current: params["current"]
    }

    model
    |> cast(params, [:fuel_capacity, :fuel_current])
    |> validate_required([:fuel_capacity, :fuel_current])
  end

  def remaining_cooldown(%__MODULE__{} = ship, now) do
    if ship.cooldown_expires_at && Timex.before?(now, ship.cooldown_expires_at) do
      Timex.diff(ship.cooldown_expires_at, now, :duration)
    else
      Timex.Duration.zero()
    end
  end

  def remaining_travel_duration(%__MODULE__{} = ship, now) do
    if ship.nav_route_arrival_at && Timex.before?(now, ship.nav_route_arrival_at) do
      Timex.diff(ship.nav_route_arrival_at, now, :duration)
    else
      Timex.Duration.zero()
    end
  end

  def cargo_current(%__MODULE__{cargo_items: cargo_items}) do
    Enum.sum_by(cargo_items, fn item -> item.units end)
  end

  def possible_travel_modes(%__MODULE__{} = ship, distance) do
    if ship.fuel_capacity > 0 do
      ~w(cruise)a
      |> Enum.filter(fn mode ->
        fuel_cost(distance)[mode] <= ship.fuel_capacity
      end)
    else
      # TODO: had some bugs when this was :drift, fix it
      ~w(cruise)a
    end
  end

  def best_travel_mode(ship, distance) do
    possible_travel_modes(ship, distance)
    |> Enum.sort_by(fn mode ->
      travel_time(ship, distance)[mode]
    end)
    |> List.first()
  end

  def travel_time(_ship, distance) do
    # TODO: add engine to the DB
    # speed = ship["engine"]["speed"]
    speed = 1

    %{
      cruise: 25,
      drift: 250,
      burn: 12.5,
      stealth: 30
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
      cruise: max(1, trunc(Float.round(distance))),
      drift: 1,
      burn: max(2, 2 * trunc(Float.round(distance))),
      stealth: max(1, trunc(Float.round(distance)))
    }
  end

  def fuel_cost(%__MODULE__{} = ship, distance) do
    case ship.nav_flight_mode do
      :cruise -> max(1, trunc(Float.round(distance)))
      :drift -> 1
      :burn -> max(2, 2 * trunc(Float.round(distance)))
      :stealth -> max(1, trunc(Float.round(distance)))
    end
  end

  def sufficient_fuel_for_travel?(%__MODULE__{} = ship, %Waypoint{} = waypoint) do
    d = Waypoint.distance(ship.nav_waypoint, waypoint)

    fuel_qty = fuel_cost(ship, d)

    ship.fuel_current >= fuel_qty
  end

  def has_saleable_cargo?(%__MODULE__{} = ship, market) do
    Enum.any?(ship.cargo_items, fn cargo_item ->
      trade_good =
        Enum.find(market.trade_goods, fn t -> t.item_symbol == cargo_item.item_symbol end)

      trade_good && trade_good.sell_price > 0
    end)
  end

  def cargo_to_sell(ship, market) do
    Enum.reject(ship.cargo_items, fn cargo_item ->
      trade_good =
        Enum.find(market.trade_goods, fn t -> t.item_symbol == cargo_item.item_symbol end)

      trade_good && is_nil(trade_good.sell_price)
    end)
  end

  def cargo_to_jettison(ship, market) do
    Enum.reject(ship.cargo_items, fn cargo_item ->
      trade_good =
        Enum.find(market.trade_goods, fn t -> t.item_symbol == cargo_item.item_symbol end)

      trade_good && trade_good.sell_price > 0
    end)
  end

  def traveling?(ship) do
    if arrival = ship.nav_route_arrival_at do
      DateTime.before?(DateTime.utc_now(), arrival)
    else
      false
    end
  end

  def has_mining_laser?(ship) do
    # TODO
    # Enum.map(ship["mounts"], fn m -> m["symbol"] end)
    # |> Enum.any?(fn mount ->
    #   mount in ~w(MOUNT_MINING_LASER_I MOUNT_MINING_LASER_II MOUNT_MINING_LASER_III)
    # end)
    ship.registration_role == "EXCAVATOR"
  end

  def has_gas_siphon?(ship) do
    # TODO
    # Enum.map(ship["mounts"], fn m -> m["symbol"] end)
    # |> Enum.any?(fn mount ->
    #   mount in ~w(MOUNT_GAS_SIPHON_I MOUNT_GAS_SIPHON_II MOUNT_GAS_SIPHON_III)
    # end)
    ship.registration_role == "COMMAND"
  end

  def has_cargo_capacity?(ship) do
    cargo_current(ship) < ship.cargo_capacity
  end
end
