defmodule SpacetradersClient.Game.Shipyard do
  use Ecto.Schema

  alias SpacetradersClient.Game.ShipyardShip

  import Ecto.Changeset

  schema "shipyards" do
    field :symbol, :string

    has_many :ships, ShipyardShip, on_replace: :delete_if_exists

    field :modification_fee, :integer
  end

  def changeset(model, params) do
    ships =
      Map.get(params, "ships", Map.get(params, "shipTypes", []))

    params = %{
      ships: ships,
      modification_fee: params["modificationsFee"]
    }

    model
    |> cast(params, [:symbol, :modification_fee])
    |> cast_assoc(:ships)
    |> validate_required([:modification_fee])
  end
end
