defmodule SpacetradersClient.Automation.ShipAutomationTick do
  use Ecto.Schema

  alias SpacetradersClient.Automation.ShipTask
  alias SpacetradersClient.Game.Ship

  schema "ship_automation_ticks" do
    field :timestamp, :utc_datetime_usec

    belongs_to :ship, Ship,
      foreign_key: :ship_symbol,
      references: :symbol,
      type: :string

    belongs_to :active_task, ShipTask

    many_to_many :alternative_tasks, ShipTask,
      join_through: "ship_automation_tick_alternative_tasks"
  end
end
