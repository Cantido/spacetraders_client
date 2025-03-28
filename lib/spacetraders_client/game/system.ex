defmodule SpacetradersClient.Game.System do
  use Ecto.Schema

  alias SpacetradersClient.Game.Sector
  alias SpacetradersClient.Game.Waypoint

  import Ecto.Changeset

  @primary_key {:symbol, :string, autogenerate: false}

  @derive {Inspect, only: [:symbol]}

  schema "systems" do
    field :sector_symbol, :string
    field :name, :string
    field :type, :string
    field :x_coordinate, :integer
    field :y_coordinate, :integer

    has_many :waypoints, Waypoint,
      foreign_key: :system_symbol,
      references: :symbol,
      preload_order: [asc: :symbol]
  end

  def changeset(model, params) do
    model
    |> cast(params, [:name, :symbol, :type])
    |> change(%{
      sector_symbol: params["sectorSymbol"],
      x_coordinate: params["x"],
      y_coordinate: params["y"]
    })
    |> validate_required([:name, :type, :sector_symbol, :x_coordinate, :y_coordinate])
  end
end
