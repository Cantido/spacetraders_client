defmodule SpacetradersClient.Game.ShipCargoItemTest do
  use ExUnit.Case

  alias SpacetradersClient.Game.Item
  alias SpacetradersClient.Game.Ship
  alias SpacetradersClient.Game.ShipCargoItem
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
    insert(:ship_cargo_item)
  end

  test "cargo_changeset puts new cargo assoc" do
    ship = insert(:ship)

    cargo_item =
      Ecto.build_assoc(ship, :cargo_items)
      |> ShipCargoItem.changeset(%{
        "symbol" => "PRECIOUS_STONES",
        "name" => "Precious stones",
        "description" => "These stones are precious",
        "units" => 1
      })
      |> Repo.insert!()

    assert cargo_item.item.symbol == "PRECIOUS_STONES"
  end
end
