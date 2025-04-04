defmodule SpacetradersClient.Finance.InventoryLineItem do
  use Ecto.Schema

  alias SpacetradersClient.Finance.Inventory

  schema "inventory_line_items" do
    belongs_to :inventory, Inventory

    field :timestamp, :utc_datetime
    field :quantity, :integer
    field :cost_per_unit, :integer
    field :total_cost, :integer
  end
end
