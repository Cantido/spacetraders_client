defmodule SpacetradersClient.Finance.TransactionLineItem do
  use Ecto.Schema

  alias SpacetradersClient.Finance.Account
  alias SpacetradersClient.Finance.Transaction

  schema "transaction_line_items" do
    belongs_to :transaction, Transaction
    belongs_to :account, Account

    field :type, Ecto.Enum, values: [:debit, :credit]
    field :amount, :integer
    field :description, :string
  end
end
