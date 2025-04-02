defmodule SpacetradersClient.Game.System do
  use Ecto.Schema

  alias SpacetradersClient.Game.Waypoint

  import Ecto.Changeset

  @primary_key {:symbol, :string, autogenerate: false}

  @derive {Inspect, only: [:symbol]}
  @derive {Jason.Encoder, except: [:__meta__, :__struct__]}

  schema "systems" do
    field :sector_symbol, :string
    field :name, :string
    field :type, :string
    field :constellation, :string
    field :x_coordinate, :integer
    field :y_coordinate, :integer

    has_many :waypoints, Waypoint,
      foreign_key: :system_symbol,
      references: :symbol,
      preload_order: [asc: :symbol]
  end

  def changeset(model, params) do
    params = %{
      symbol: params["symbol"],
      name: params["name"],
      type: params["type"],
      constellation: params["constellation"],
      sector_symbol: params["sectorSymbol"],
      x_coordinate: params["x"],
      y_coordinate: params["y"],
      waypoints: params["waypoints"]
    }

    model
    |> cast(params, [
      :name,
      :symbol,
      :type,
      :constellation,
      :sector_symbol,
      :x_coordinate,
      :y_coordinate
    ])
    |> cast_assoc(:waypoints)
    |> validate_required([
      :name,
      :symbol,
      :type,
      :constellation,
      :sector_symbol,
      :x_coordinate,
      :y_coordinate
    ])
  end
end
