defmodule SpacetradersClient.Finance.Account do
  use Ecto.Schema

  alias SpacetradersClient.Finance.TransactionLineItem
  alias SpacetradersClient.Game.Agent

  schema "accounts" do
    belongs_to :agent, Agent, foreign_key: :agent_symbol, references: :symbol, type: :string

    has_one :parent_account, __MODULE__
    has_many :subaccounts, __MODULE__, preload_order: [asc: :number]

    has_many :line_items, TransactionLineItem

    field :name, :string
    field :number, :integer
    field :type, Ecto.Enum, values: ~w(assets liabilities equity revenue expenses)a

    field :current, :boolean, default: true
    field :direct_cost, :boolean, default: false
  end
end
