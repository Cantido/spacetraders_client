defmodule SpacetradersClient.Repo.Migrations.AddFleet do
  use Ecto.Migration

  def change do
    create table(:agents) do
      add :symbol, :string, null: false
      add :token, :string, null: false, size: 1024
      add :credits, :integer, null: false
      add :automation_enabled, :boolean, default: false

      timestamps()
    end

    create unique_index(:agents, [:symbol])

    create table(:ships) do
      add :symbol, :string, null: false

      add :agent_id,
          references(:agents,
            on_update: :update_all,
            on_delete: :delete_all
          ),
          null: false

      add :registration_role, :string, null: false

      add :nav_waypoint_id,
          references(:waypoints,
            on_update: :update_all,
            on_delete: :delete_all
          ),
          null: false

      add :nav_route_destination_waypoint_id,
          references(:waypoints,
            on_update: :update_all,
            on_delete: :delete_all
          ),
          null: false

      add :nav_route_origin_waypoint_id,
          references(:waypoints,
            on_update: :update_all,
            on_delete: :delete_all
          ),
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

    create unique_index(:ships, [:symbol])

    create table(:items) do
      add :symbol, :string, null: false

      add :name, :string, null: false
      add :description, :string, null: false
    end

    create unique_index(:items, [:symbol])

    create table(:ship_cargo_items) do
      add :ship_id,
          references(:ships,
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

      add :units, :integer, null: false

      timestamps()
    end

    create unique_index(:ship_cargo_items, [:ship_id, :item_id])
  end
end
