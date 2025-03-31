defmodule SpacetradersClient.Automation.ShipTaskCondition do
  use Ecto.Schema

  alias SpacetradersClient.Automation.ShipTask

  @primary_key false

  schema "ship_task_conditions" do
    belongs_to :ship_task, ShipTask, primary_key: true

    field :name, :string, primary_key: true
  end
end
