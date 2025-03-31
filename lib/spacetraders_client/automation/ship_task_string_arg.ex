defmodule SpacetradersClient.Automation.ShipTaskStringArg do
  use Ecto.Schema

  alias SpacetradersClient.Automation.ShipTask

  @primary_key false

  schema "ship_task_string_args" do
    belongs_to :ship_task, ShipTask, primary_key: true

    field :name, :string, primary_key: true
    field :value, :string
  end
end
