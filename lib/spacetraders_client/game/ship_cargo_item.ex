defmodule SpacetradersClient.Game.ShipCargoItem do
  use Ecto.Schema

  alias SpacetradersClient.Game.Item
  alias SpacetradersClient.Game.Ship

  import Ecto.Changeset

  schema "ship_cargo_items" do
    belongs_to :ship, Ship, on_replace: :delete

    belongs_to :item, Item, on_replace: :delete

    field :units, :integer

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(model, params) do
    item =
      %Item{
        symbol: params["symbol"],
        name: params["name"],
        description: params["description"]
      }

    model
    |> cast(params, [:units])
    |> put_assoc(:item, item)
    |> assoc_constraint(:ship)
    |> assoc_constraint(:item)
  end
end
