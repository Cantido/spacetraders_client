defmodule SpacetradersClient.Game.ShipyardShip do
  use Ecto.Schema

  alias SpacetradersClient.Game.Shipyard

  import Ecto.Changeset

  schema "shipyard_ships" do
    belongs_to :shipyard, Shipyard

    field :type, :string
    field :name, :string
    field :description, :string
    field :supply, :string
    field :activity, :string
    field :purchase_price, :integer
  end

  def changeset(model, params) do
    params =
      Map.merge(params, %{
        "purchase_price" => params["purchasePrice"]
      })

    model
    |> cast(params, [:type, :name, :description, :supply, :activity, :purchase_price])
  end
end
