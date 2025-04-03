defmodule SpacetradersClient.Game.Item do
  use Ecto.Schema

  alias SpacetradersClient.Game.ShipCargoItem

  import Ecto.Changeset

  schema "items" do
    field :symbol, :string
    field :name, :string
    field :description, :string
  end

  def changeset(model, params) do
    model
    |> cast(params, [:symbol, :name, :description])
    |> validate_required([:symbol, :name, :description])
  end
end
