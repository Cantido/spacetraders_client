defmodule SpacetradersClient.Game.Item do
  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:symbol, :string, autogenerate: false}

  schema "items" do
    field :name, :string
    field :description, :string
  end

  def changeset(model, params) do
    model
    |> cast(params, [:symbol, :name, :description])
    |> validate_required([:symbol, :name, :description])
  end
end
