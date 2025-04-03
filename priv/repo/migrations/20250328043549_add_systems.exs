defmodule SpacetradersClient.Repo.Migrations.AddSystems do
  use Ecto.Migration

  def change do
    create table(:systems) do
      add :symbol, :string, null: false
      add :sector_symbol, :string, null: false

      add :name, :string, null: false
      add :type, :string, null: false
      add :constellation, :string, null: false
      add :x_coordinate, :integer, null: false
      add :y_coordinate, :integer, null: false
    end

    create unique_index(:systems, [:symbol])

    create table(:waypoints) do
      add :symbol, :string, null: false

      add :system_id,
          references(:systems,
            on_update: :update_all,
            on_delete: :delete_all
          ),
          null: false

      add :orbits_waypoint_id,
          references(:waypoints,
            on_update: :update_all,
            on_delete: :delete_all
          )

      add :type, :string, null: false
      add :x_coordinate, :integer, null: false
      add :y_coordinate, :integer, null: false
      add :under_construction, :boolean

      timestamps()
    end

    create unique_index(:waypoints, [:symbol])

    create table(:waypoint_traits) do
      add :waypoint_id,
          references(:waypoints,
            on_update: :update_all,
            on_delete: :delete_all
          )

      add :symbol, :string, primary_key: true
      add :name, :string
      add :description, :string
    end

    create unique_index(:waypoint_traits, [:waypoint_id, :symbol])

    create table(:waypoint_modifiers) do
      add :waypoint_id,
          references(:waypoints,
            on_update: :update_all,
            on_delete: :delete_all
          ),
          null: false

      add :symbol, :string, null: false
      add :name, :string
      add :description, :string
    end

    create unique_index(:waypoint_modifiers, [:waypoint_id, :symbol])
  end
end
