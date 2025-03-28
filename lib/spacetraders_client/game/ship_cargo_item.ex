defmodule SpacetradersClient.Game.ShipCargoItem do
  use Ecto.Schema

  alias SpacetradersClient.Game.Item
  alias SpacetradersClient.Game.Ship

  import Ecto.Changeset

  @primary_key false

  schema "items" do
    belongs_to :ship, Ship,
      foreign_key: :ship_symbol,
      references: :symbol,
      type: :string,
      primary_key: true

    belongs_to :item, Item,
      foreign_key: :item_symbol,
      references: :symbol,
      type: :string,
      primary_key: true

    field :units, :integer

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(model, params) do
    model
    |> cast(params, [:units])
    |> cast_assoc(:item)
    |> assoc_constraint(:ship)
    |> assoc_constraint(:item)
  end
end
