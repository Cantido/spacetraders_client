defmodule SpacetradersClient.Repo.Migrations.AddShipyards do
  use Ecto.Migration

  def change do
    create table(:shipyards) do
      add :symbol, :string, null: false

      add :modification_fee, :integer, null: false
    end

    create table(:shipyard_ships) do
      add :shipyard_id,
          references(:shipyards,
            on_update: :update_all,
            on_delete: :delete_all
          ),
          null: false

      add :type, :string

      add :name, :string
      add :description, :string
      add :supply, :string
      add :activity, :string
      add :purchase_price, :integer
    end

    create unique_index(:shipyard_ships, [:shipyard_id, :type])
  end
end
