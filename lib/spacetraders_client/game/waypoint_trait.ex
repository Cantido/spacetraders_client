defmodule SpacetradersClient.Game.WaypointTrait do
  use Ecto.Schema

  alias SpacetradersClient.Game.Waypoint

  import Ecto.Changeset

  @primary_key false

  @derive {Jason.Encoder, except: [:__meta__, :__struct__, :waypoint]}

  schema "waypoint_traits" do
    belongs_to :waypoint, Waypoint,
      primary_key: true,
      foreign_key: :waypoint_symbol,
      references: :symbol,
      type: :string

    field :symbol, :string, primary_key: true
    field :name, :string
    field :description, :string
  end

  def changeset(model, params) do
    model
    |> cast(params, [:symbol, :name, :description])
    |> assoc_constraint(:waypoint)
    |> unique_constraint([:symbol, :waypoint_symbol],
      name: "waypoint_traits_waypoint_symbol_symbol_index",
      message: "waypoint already has this trait"
    )
  end
end
