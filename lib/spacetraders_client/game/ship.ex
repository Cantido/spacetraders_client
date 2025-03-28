defmodule SpacetradersClient.Game.Ship do
  use Ecto.Schema

  alias SpacetradersClient.Game.Agent
  alias SpacetradersClient.Game.Waypoint
  alias SpacetradersClient.Game.ShipCargoItem

  import Ecto.Changeset

  @primary_key {:symbol, :string, autogenerate: false}

  schema "ships" do
    belongs_to :agent, Agent, foreign_key: :agent_symbol, references: :symbol, type: :string

    belongs_to :nav_waypoint, Waypoint,
      foreign_key: :nav_waypoint_symbol,
      references: :symbol,
      type: :string

    field :registration_role, :string

    belongs_to :nav_route_destination_waypoint, Waypoint,
      foreign_key: :nav_route_destination_waypoint_symbol,
      references: :symbol,
      type: :string

    belongs_to :nav_route_origin_waypoint, Waypoint,
      foreign_key: :nav_route_origin_waypoint_symbol,
      references: :symbol,
      type: :string

    field :nav_route_departure_at, :utc_datetime_usec
    field :nav_route_arrival_at, :utc_datetime_usec

    field :nav_status, Ecto.Enum,
      values: [in_transit: "IN_TRANSIT", in_orbit: "IN_ORBIT", docked: "DOCKED"]

    field :nav_flight_mode, Ecto.Enum,
      values: [drift: "DRIFT", stealth: "STEALTH", cruise: "CRUISE", burn: "BURN"]

    field :cooldown_total_seconds, :integer
    field :cooldown_expires_at, :utc_datetime_usec

    field :cargo_capacity, :integer

    has_many :cargo_items, ShipCargoItem

    field :fuel_capacity, :integer
    field :fuel_current, :integer

    timestamps(type: :utc_datetime_usec)
  end

  @required_params [
    :symbol,
    :registration_role,
    :nav_waypoint_symbol,
    :nav_route_destination_waypoint_symbol,
    :nav_route_origin_waypoint_symbol,
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
    # :cooldown_expires_at
  ]

  @allowed_params @required_params ++ @optional_params

  def changeset(model, params) do
    params = %{
      symbol: params["symbol"],
      registration_role: params["registration"]["role"],
      nav_waypoint_symbol: params["nav"]["waypointSymbol"],
      nav_route_destination_waypoint_symbol: params["nav"]["route"]["destination"]["symbol"],
      nav_route_origin_waypoint_symbol: params["nav"]["route"]["origin"]["symbol"],
      nav_route_departure_at: params["nav"]["route"]["departureTime"],
      nav_route_arrival_at: params["nav"]["route"]["arrival"],
      nav_status: params["nav"]["status"],
      nav_flight_mode: params["nav"]["flightMode"],
      cooldown_total_seconds: params["cooldown"]["totalSeconds"],
      cooldown_expires_at: params["cooldown"]["expiration"],
      cargo_capacity: params["cargo"]["capacity"],
      cargo_items:
        Enum.map(params["cargo"]["inventory"], fn item ->
          %{
            item: %{
              symbol: item["symbol"],
              name: item["name"],
              description: item["description"]
            },
            units: item["units"]
          }
        end),
      fuel_capacity: params["fuel"]["capacity"],
      fuel_current: params["fuel"]["current"]
    }

    model
    |> cast(params, @allowed_params)
    # |> cast_assoc(:cargo_items)
    |> validate_required([:agent_symbol] ++ @required_params)
    |> assoc_constraint(:agent)
  end
end
