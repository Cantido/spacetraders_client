defmodule SpacetradersClient.Automation.AutomationTick do
  use Ecto.Schema

  alias SpacetradersClient.Automation.ShipAutomationTick

  schema "automation_ticks" do
    field :timestamp, :utc_datetime_usec

    has_many :ship_automation_ticks, ShipAutomationTick
  end
end
