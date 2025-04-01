defmodule SpacetradersClient.Finance.Transaction do
  use Ecto.Schema

  alias SpacetradersClient.Finance.TransactionLineItem

  import Ecto.Changeset

  schema "transactions" do
    field :timestamp, :utc_datetime
    field :description, :string

    has_many :line_items, TransactionLineItem
  end

  def simple(timestamp, description, debit_account_id, credit_account_id, amount) do
    params = %{
      timestamp: timestamp,
      description: description
    }

    %__MODULE__{}
    |> cast(params, [:timestamp, :description])
    |> add_debit(amount, debit_account_id, description)
    |> add_credit(amount, credit_account_id, description)
  end

  def add_debit(tx, amount, account_id, description) do
    line =
      %TransactionLineItem{
        type: :debit,
        account_id: account_id,
        description: description,
        amount: trunc(amount)
      }
      |> change()

    tx = change(tx)

    put_assoc(tx, :line_items, [line | get_field(tx, :line_items)])
  end

  def add_credit(tx, amount, account_id, description) do
    line =
      %TransactionLineItem{
        type: :credit,
        account_id: account_id,
        description: description,
        amount: trunc(amount)
      }
      |> change()

    tx = change(tx)

    put_assoc(tx, :line_items, [line | get_field(tx, :line_items)])
  end

  def validate_balanced(changeset) do
    validate_change(changeset, :line_items, fn _, line_items ->
      debits =
        line_items
        |> Enum.filter(fn li -> li.type == :debit end)
        |> Enum.map(fn li -> li.amount end)
        |> Enum.sum()

      credits =
        line_items
        |> Enum.filter(fn li -> li.type == :credit end)
        |> Enum.map(fn li -> li.amount end)
        |> Enum.sum()

      if debits == credits do
        []
      else
        [line_items: "debits and credits must balance"]
      end
    end)
  end
end
