defmodule SpacetradersClient.Game.ItemTest do
  use ExUnit.Case

  alias SpacetradersClient.Game.Item
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
    insert(:item)
  end

  test "changeset insert" do
    item =
      %Item{
        symbol: "PRECIOUS_STONES"
      }
      |> Item.changeset(%{
        "name" => "Precious stones",
        "description" => "These stones are precious"
      })
      |> Repo.insert!()

    assert item.symbol == "PRECIOUS_STONES"
    assert item.name == "Precious stones"
    assert item.description == "These stones are precious"
  end

  test "changeset change" do
    item =
      insert(:item)
      |> Item.changeset(%{
        "name" => "Precious stones",
        "description" => "These stones are precious"
      })
      |> Repo.update!()

    assert item.name == "Precious stones"
    assert item.description == "These stones are precious"
  end
end
