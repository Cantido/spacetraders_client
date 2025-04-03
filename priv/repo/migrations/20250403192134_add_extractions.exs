defmodule SpacetradersClient.Repo.Migrations.AddExtractions do
  use Ecto.Migration

  def change do
    create table(:extractions) do
      add :ship_id, references(:ships, on_update: :update_all, on_delete: :delete_all),
        null: false

      add :item_id, references(:items, on_update: :update_all, on_delete: :delete_all),
        null: false

      add :waypoint_id, references(:waypoints, on_update: :update_all, on_delete: :delete_all),
        null: false

      add :units, :integer, null: false
    end
  end
end
