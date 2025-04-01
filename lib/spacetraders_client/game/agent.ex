defmodule SpacetradersClient.Game.Agent do
  use Ecto.Schema

  alias SpacetradersClient.Game.Ship
  alias SpacetradersClient.Finance.Account

  import Ecto.Changeset

  @primary_key {:symbol, :string, autogenerate: false}

  schema "agents" do
    field :credits, :integer
    field :token, :string
    field :automation_enabled, :boolean

    has_many :ships, Ship, preload_order: [asc: :symbol]
    has_many :accounts, Account, preload_order: [asc: :number]

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(model, params) do
    model
    |> cast(params, [:symbol, :credits, :token])
    |> validate_required([:symbol, :credits])
    |> validate_number(:credits, greater_than_or_equal_to: 0)
  end
end
