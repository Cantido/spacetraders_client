defmodule SpacetradersClient.Automation.ShipAutomationTick do
  use Ecto.Schema

  alias SpacetradersClient.Automation.AutomationTick
  alias SpacetradersClient.Automation.ShipTask

  schema "ship_automation_ticks" do
    field :timestamp, :utc_datetime_usec

    belongs_to :ship, Ship,
      foreign_key: :ship_symbol,
      references: :symbol,
      type: :string

    belongs_to :active_task, ShipTask
    has_many :alternative_tasks, {"ship_automation_tick_alternative_tasks", ShipTask}
  end
end
