defmodule SpacetradersClient.Repo.Migrations.AddShipyards do
  use Ecto.Migration

  def change do
    create table(:shipyards, primary_key: false) do
      add :symbol, :string, primary_key: true

      add :modification_fee, :integer, null: false
    end

    create table(:shipyard_ships, primary_key: false) do
      add :shipyard_symbol,
          references(:shipyards, column: :symbol, on_update: :update_all, on_delete: :delete_all),
          primary_key: true

      add :type, :string, primary_key: true

      add :name, :string
      add :description, :string
      add :supply, :string
      add :activity, :string
      add :purchase_price, :integer
    end
  end
end
