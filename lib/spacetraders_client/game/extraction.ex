defmodule SpacetradersClient.Game.Extraction do
  use Ecto.Schema

  alias SpacetradersClient.Game.Ship
  alias SpacetradersClient.Game.Item
  alias SpacetradersClient.Game.Waypoint

  schema "extractions" do
    belongs_to :ship, Ship
    belongs_to :item, Item
    belongs_to :waypoint, Waypoint

    field :units, :integer
  end
end
