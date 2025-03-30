defmodule SpacetradersClient.Finance.InventoryLineItem do
  use Ecto.Schema

  alias SpacetradersClient.Finance.Inventory

  schema "inventory_line_items" do
    belongs_to :inventory, Inventory

    field :timestamp, :utc_datetime_usec
    field :quantity, :integer
    field :cost_per_unit, :integer
    field :total_cost, :integer
  end

  def purchase_inventory_by_unit(inventory_id, timestamp, quantity, cost_per_unit) do
    %__MODULE__{
      inventory_id: inventory_id,
      timestamp: timestamp,
      quantity: quantity,
      cost_per_unit: cost_per_unit,
      total_cost: quantity * cost_per_unit
    }
  end

  def purchase_inventory_by_total(inventory_id, timestamp, quantity, total_cost) do
    %__MODULE__{
      inventory_id: inventory_id,
      timestamp: timestamp,
      quantity: quantity,
      cost_per_unit: div(total_cost, quantity),
      total_cost: total_cost
    }
  end
end
