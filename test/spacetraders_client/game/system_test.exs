defmodule SpacetradersClient.SystemTest do
  use ExUnit.Case

  alias SpacetradersClient.Game.System
  alias SpacetradersClient.Game.Waypoint
  alias SpacetradersClient.Repo

  import SpacetradersClient.Factory

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(SpacetradersClient.Repo)
  end

  setup tags do
    pid =
      Ecto.Adapters.SQL.Sandbox.start_owner!(SpacetradersClient.Repo, shared: not tags[:async])

    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)
    :ok
  end

  test "factory" do
    insert(:system)
  end

  test "cast associated waypoints" do
    system =
      %System{}
      |> System.changeset(%{
        "symbol" => "X1-ASDF",
        "sectorSymbol" => "…",
        "constellation" => "…",
        "name" => "…",
        "type" => "NEUTRON_STAR",
        "x" => 1,
        "y" => 1,
        "waypoints" => [
          %{
            "symbol" => "X1-ASDF-1",
            "type" => "PLANET",
            "systemSymbol" => "X1-ASDF",
            "x" => 1,
            "y" => 1
          }
        ]
      })
      |> Repo.insert!()
      |> Repo.preload(:waypoints)

    [waypoint] = system.waypoints

    assert waypoint.symbol == "X1-ASDF-1"
  end
end
