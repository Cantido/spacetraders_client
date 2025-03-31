defmodule SpacetradersClient.Automation.ShipTaskFloatArg do
  use Ecto.Schema

  alias SpacetradersClient.Automation.ShipTask

  @primary_key false

  schema "ship_task_float_args" do
    belongs_to :ship_task, ShipTask, primary_key: true

    field :name, :string, primary_key: true
    field :value, :float
  end
end
