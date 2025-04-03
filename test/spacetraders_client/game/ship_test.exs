defmodule SpacetradersClient.Game.ShipTest do
  use ExUnit.Case

  alias SpacetradersClient.Game.Item
  alias SpacetradersClient.Game.Ship
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
    insert(:ship)
  end

  test "cargo_changeset puts new cargo assoc" do
    ship =
      insert(:ship)
      |> Repo.preload(:cargo_items)
      |> Ship.cargo_changeset(%{
        "inventory" => [
          %{
            "symbol" => "PRECIOUS_STONES",
            "name" => "Precious stones",
            "description" => "These stones are precious",
            "units" => 1
          }
        ]
      })
      |> Repo.update!()
      |> Repo.preload(cargo_items: [:item])

    assert [cargo_item] = ship.cargo_items
    assert cargo_item.item_symbol == "PRECIOUS_STONES"
  end

  test "cargo_changeset puts existing item in cargo" do
    %Item{}
    |> Item.changeset(%{
      "symbol" => "PRECIOUS_STONES",
      "name" => "Precious stones",
      "description" => "These stones are precious"
    })
    |> Repo.insert!()

    insert(:ship)
    |> Repo.preload(:cargo_items)
    |> Ship.cargo_changeset(%{
      "inventory" => [
        %{
          "symbol" => "PRECIOUS_STONES",
          "name" => "Precious stones",
          "description" => "These stones are precious",
          "units" => 1
        }
      ]
    })
    |> Repo.update!()
  end
end
