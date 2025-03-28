defmodule SpacetradersClient.Game.Agent do
  use Ecto.Schema

  alias SpacetradersClient.Game.Ship

  import Ecto.Changeset

  @primary_key {:symbol, :string, autogenerate: false}

  schema "agents" do
    field :credits, :integer

    has_many :ships, Ship

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(model, params) do
    model
    |> cast(params, [:symbol, :credits])
    |> validate_required([:symbol, :credits])
    |> validate_number(:credits, greater_than_or_equal_to: 0)
  end
end
