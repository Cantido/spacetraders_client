defmodule SpacetradersClient.Automation.DecisionFactor do
  use Ecto.Schema

  alias SpacetradersClient.Automation.ShipTask

  schema "decision_factors" do
    belongs_to :ship_task, ShipTask

    field :name, :string
    field :input_value, :float
    field :output_value, :float
    field :weight, :float
  end
end
