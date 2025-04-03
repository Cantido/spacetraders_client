defmodule SpacetradersClient.Repo.Migrations.AddWaypointOptions do
  use Ecto.Migration

  def change do
    create table(:markets) do
      add :symbol, :string, null: false
    end

    create unique_index(:markets, [:symbol])

    create table(:market_trade_goods) do
      add :market_id,
          references(:markets,
            on_update: :update_all,
            on_delete: :delete_all
          ),
          null: false

      add :item_id,
          references(:items,
            on_update: :update_all,
            on_delete: :delete_all
          ),
          null: false

      add :type, :string, null: false
      add :trade_volume, :integer
      add :supply, :string
      add :activity, :string
      add :purchase_price, :integer
      add :sell_price, :integer

      timestamps()
    end

    create unique_index(:market_trade_goods, [:market_id, :item_id])
  end
end
