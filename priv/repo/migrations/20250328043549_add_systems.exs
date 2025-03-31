defmodule SpacetradersClient.Repo.Migrations.AddSystems do
  use Ecto.Migration

  def change do
    create table(:systems, primary_key: false) do
      add :symbol, :string, primary_key: true
      add :sector_symbol, :string, null: false

      add :name, :string, null: false
      add :type, :string, null: false
      add :constellation, :string, null: false
      add :x_coordinate, :integer, null: false
      add :y_coordinate, :integer, null: false
    end

    create table(:waypoints, primary_key: false) do
      add :symbol, :string, primary_key: true

      add :system_symbol,
          references(:systems, column: :symbol, on_update: :update_all, on_delete: :delete_all),
          null: false

      add :orbits_waypoint_symbol,
          references(:waypoints, column: :symbol, on_update: :update_all, on_delete: :delete_all)

      add :type, :string, null: false
      add :x_coordinate, :integer, null: false
      add :y_coordinate, :integer, null: false
      add :under_construction, :boolean

      timestamps()
    end

    create table(:waypoint_traits, primary_key: false) do
      add :waypoint_symbol,
          references(:waypoints, column: :symbol, on_update: :update_all, on_delete: :delete_all),
          primary_key: true

      add :symbol, :string, primary_key: true
      add :name, :string
      add :description, :string
    end

    create table(:waypoint_modifiers, primary_key: false) do
      add :waypoint_symbol,
          references(:waypoints, column: :symbol, on_update: :update_all, on_delete: :delete_all),
          primary_key: true

      add :symbol, :string, primary_key: true
      add :name, :string
      add :description, :string
    end
  end
end
