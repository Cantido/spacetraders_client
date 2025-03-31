defmodule SpacetradersClient.Repo.Migrations.AddWaypointOptions do
  use Ecto.Migration

  def change do
    create table(:markets, primary_key: false) do
      add :symbol, :string, primary_key: true
    end

    create table(:market_trade_goods, primary_key: false) do
      add :market_symbol,
          references(:markets, column: :symbol, on_update: :update_all, on_delete: :delete_all),
          primary_key: true

      add :item_symbol,
          references(:items, column: :symbol, on_update: :update_all, on_delete: :delete_all),
          primary_key: true

      add :type, :string, null: false
      add :trade_volume, :integer
      add :supply, :string
      add :activity, :string
      add :purchase_price, :integer
      add :sell_price, :integer

      timestamps()
    end
  end
end
