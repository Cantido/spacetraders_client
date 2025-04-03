defmodule SpacetradersClient.Game.WaypointModifier do
  use Ecto.Schema

  alias SpacetradersClient.Game.Waypoint

  import Ecto.Changeset

  @primary_key false
  @derive {Jason.Encoder, except: [:__meta__, :__struct__, :waypoint]}

  schema "waypoint_modifiers" do
    belongs_to :waypoint, Waypoint

    field :symbol, :string, primary_key: true
    field :name, :string
    field :description, :string
  end

  def changeset(model, params) do
    model
    |> cast(params, [:symbol, :name, :description])
    |> assoc_constraint(:waypoint)
  end
end
