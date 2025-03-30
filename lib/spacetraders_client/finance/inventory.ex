defmodule SpacetradersClient.Finance.Inventory do
  use Ecto.Schema

  alias SpacetradersClient.Finance.InventoryLineItem
  alias SpacetradersClient.Game.Agent
  alias SpacetradersClient.Game.Item

  schema "inventories" do
    belongs_to :agent, Agent, foreign_key: :agent_symbol, references: :symbol, type: :string
    belongs_to :item, Item, foreign_key: :item_symbol, references: :symbol, type: :string

    has_many :line_items, InventoryLineItem
  end
end
