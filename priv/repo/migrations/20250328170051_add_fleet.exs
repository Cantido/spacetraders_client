defmodule SpacetradersClient.Repo.Migrations.AddFleet do
  use Ecto.Migration

  def change do
    create table(:agents, primary_key: false) do
      add :symbol, :string, primary_key: true
      add :token, :string, null: false
      add :credits, :integer, null: false
      add :automation_enabled, :boolean, default: false

      timestamps()
    end

    create table(:ships, primary_key: false) do
      add :symbol, :string, primary_key: true

      add :agent_symbol,
          references(:agents, column: :symbol, on_update: :update_all, on_delete: :delete_all),
          null: false

      add :registration_role, :string, null: false

      add :nav_waypoint_symbol,
          references(:waypoints, column: :symbol, on_update: :update_all, on_delete: :delete_all),
          null: false

      add :nav_route_destination_waypoint_symbol,
          references(:waypoints, column: :symbol, on_update: :update_all, on_delete: :delete_all),
          null: false

      add :nav_route_origin_waypoint_symbol,
          references(:waypoints, column: :symbol, on_update: :update_all, on_delete: :delete_all),
          null: false

      add :nav_route_departure_at, :utc_datetime_usec, null: false
      add :nav_route_arrival_at, :utc_datetime_usec, null: false

      add :nav_status, :string, null: false
      add :nav_flight_mode, :string, null: false

      add :cooldown_total_seconds, :integer, null: false
      add :cooldown_expires_at, :utc_datetime_usec

      add :cargo_capacity, :integer, null: false

      add :fuel_capacity, :integer, null: false
      add :fuel_current, :integer, null: false

      timestamps()
    end

    create table(:items, primary_key: false) do
      add :symbol, :string, primary_key: true

      add :name, :string, null: false
      add :description, :string, null: false
    end

    create table(:ship_cargo_items, primary_key: false) do
      add :ship_symbol,
          references(:ships, column: :symbol, on_update: :update_all, on_delete: :delete_all),
          primary_key: true

      add :item_symbol,
          references(:items, column: :symbol, on_update: :update_all, on_delete: :delete_all),
          primary_key: true

      add :units, :integer, null: false

      timestamps()
    end
  end
end
