defmodule SpacetradersClient.Repo.Migrations.AddAutomation do
  use Ecto.Migration

  def change do
    create table(:ship_tasks) do
      add :name, :string, null: false
      add :utility, :float, null: false
    end

    create table(:decision_factors) do
      add :ship_task_id,
          references(:ship_tasks, on_update: :update_all, on_delete: :delete_all),
          null: false

      add :name, :string, null: false

      add :input_value, :float, null: false
      add :output_value, :float, null: false
      add :weight, :float, null: false
    end

    create unique_index(:decision_factors, [:ship_task_id, :name])

    create table(:ship_task_string_args, primary_key: false) do
      add :ship_task_id,
          references(:ship_tasks, on_update: :update_all, on_delete: :delete_all),
          primary_key: true

      add :name, :string, primary_key: true
      add :value, :string, null: false
    end

    create table(:ship_task_float_args, primary_key: false) do
      add :ship_task_id,
          references(:ship_tasks, on_update: :update_all, on_delete: :delete_all),
          primary_key: true

      add :name, :string, primary_key: true
      add :value, :float, null: false
    end

    create table(:ship_task_conditions) do
      add :ship_task_id,
          references(:ship_tasks, on_update: :update_all, on_delete: :delete_all),
          primary_key: true

      add :name, :string, null: false
    end

    create unique_index(:ship_task_conditions, [:ship_task_id, :name])

    create table(:ship_automation_ticks) do
      add :timestamp, :utc_datetime_usec, null: false

      add :ship_id,
          references(:ships,
            on_update: :update_all,
            on_delete: :delete_all
          )

      add :active_task_id,
          references(:ship_tasks, on_update: :update_all, on_delete: :delete_all)
    end

    create table(:ship_automation_tick_alternative_tasks, primary_key: false) do
      add :ship_automation_tick_id,
          references(:ship_automation_ticks, on_update: :update_all, on_delete: :delete_all),
          primary_key: true

      add :ship_task_id,
          references(:ship_tasks, on_update: :update_all, on_delete: :delete_all),
          primary_key: true
    end
  end
end
