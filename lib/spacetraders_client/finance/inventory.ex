defmodule SpacetradersClient.Finance.Inventory do
  use Ecto.Schema

  alias SpacetradersClient.Finance.InventoryLineItem
  alias SpacetradersClient.Game.Agent
  alias SpacetradersClient.Game.Item

  schema "inventories" do
    belongs_to :agent, Agent
    belongs_to :item, Item

    has_many :line_items, InventoryLineItem
  end
end
