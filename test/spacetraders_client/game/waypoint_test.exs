defmodule SpacetradersClient.WaypointTest do
  use ExUnit.Case

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
    insert(:waypoint)
  end
end
