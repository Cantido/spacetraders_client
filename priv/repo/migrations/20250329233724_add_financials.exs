defmodule SpacetradersClient.Repo.Migrations.AddFinancials do
  use Ecto.Migration

  def change do
    create table(:accounts) do
      add :agent_symbol,
          references(:agents, column: :symbol, on_update: :update_all, on_delete: :delete_all),
          null: false

      add :parent_account_id,
          references(:accounts, on_update: :update_all, on_delete: :delete_all)

      add :name, :string, null: false
      add :type, :string, null: false
      add :number, :integer, null: false
      add :current, :boolean, default: true
      add :direct_cost, :boolean, default: false
    end

    create table(:transactions) do
      add :description, :string
      add :timestamp, :utc_datetime_usec, null: false
    end

    create table(:transaction_line_items) do
      add :transaction_id,
          references(:transactions, on_update: :update_all, on_delete: :delete_all),
          null: false

      add :type, :string, null: false
      add :amount, :integer, null: false

      add :account_id, references(:accounts, on_update: :update_all, on_delete: :delete_all),
        null: false

      add :description, :string
    end

    create table(:inventories) do
      add :agent_symbol,
          references(:agents, column: :symbol, on_update: :update_all, on_delete: :delete_all),
          null: false

      add :item_symbol,
          references(:items, column: :symbol, on_update: :update_all, on_delete: :delete_all),
          null: false
    end

    create unique_index(:inventories, [:agent_symbol, :item_symbol])

    create table(:inventory_line_items) do
      add :inventory_id,
          references(:inventories, on_update: :update_all, on_delete: :delete_all),
          null: false

      add :timestamp, :utc_datetime_usec, null: false
      add :quantity, :integer, null: false
      add :cost_per_unit, :integer, null: false
      add :total_cost, :integer, null: false
    end
  end
end
