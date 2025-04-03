defmodule SpacetradersClient.Factory do
  use ExMachina.Ecto, repo: SpacetradersClient.Repo

  alias SpacetradersClient.Game.Agent
  alias SpacetradersClient.Game.Item
  alias SpacetradersClient.Game.Ship
  alias SpacetradersClient.Game.System
  alias SpacetradersClient.Game.Waypoint

  def agent_factory do
    %Agent{
      symbol: sequence(:agent_symbol, &"#{Faker.Nato.callsign()}-#{&1}"),
      credits: Enum.random(100_000..250_000//1),
      token: :crypto.strong_rand_bytes(100) |> Base.encode64()
    }
  end

  def system_factory do
    %System{
      sector_symbol: "X1",
      symbol: sequence(:system_symbol, &"X1-#{&1}"),
      name: Faker.StarWars.planet(),
      type: Enum.random(~w(
        NEUTRON_STAR
        RED_STAR
        ORANGE_STAR
        BLUE_STAR
        YOUNG_STAR
        WHITE_DWARF
        BLACK_HOLE
        HYPERGIANT
        NEBULA
        UNSTABLE
      )),
      constellation: Faker.StarWars.planet(),
      x_coordinate: Enum.random(-100..100//1),
      y_coordinate: Enum.random(-100..100//1)
    }
  end

  def waypoint_factory do
    %Waypoint{
      symbol: sequence(:waypoint_symbol, &"X1-TEST-#{&1}"),
      system: build(:system),
      type: Enum.random(~w(
        PLANET
        GAS_GIANT
        MOON
        ORBITAL_STATION
        JUMP_GATE
        ASTEROID_FIELD
        ASTEROID
        ENGINEERED_ASTEROID
        ASTEROID_BASE
        NEBULA
        DEBRIS_FIELD
        GRAVITY_WELL
        ARTIFICIAL_GRAVITY_WELL
        FUEL_STATION
      )),
      x_coordinate: Enum.random(-100..100//1),
      y_coordinate: Enum.random(-100..100//1),
      under_construction: Enum.random([true, false])
    }
  end

  def ship_factory do
    %Ship{
      symbol: sequence(:ship_symbol, &"TEST-AGENT-#{&1}"),
      agent: build(:agent),
      nav_waypoint: build(:waypoint),
      registration_role: Enum.random(~w(
        FABRICATOR
        HARVESTER
        HAULER
        INTERCEPTOR
        EXCAVATOR
        TRANSPORT
        REPAIR
        SURVEYOR
        COMMAND
        CARRIER
        PATROL
        SATELLITE
        EXPLORER
        REFINERY
      )),
      nav_route_destination_waypoint: build(:waypoint),
      nav_route_origin_waypoint: build(:waypoint),
      nav_route_departure_at: Faker.DateTime.backward(1),
      nav_route_arrival_at: Faker.DateTime.forward(1),
      nav_status: Enum.random(~w(in_transit in_orbit docked)a),
      nav_flight_mode: Enum.random(~w(cruise burn drift stealth)a),
      cooldown_total_seconds: Enum.random(0..120),
      cooldown_expires_at: Faker.DateTime.backward(1),
      fuel_capacity: 100,
      fuel_current: Enum.random(10..100),
      cargo_capacity: 100
    }
  end

  def item_factory do
    %Item{
      symbol: sequence(:item_symbol, &"TEST_ITEM_#{&1}"),
      name: "Test Item",
      description: "Test Item Description"
    }
  end
end
