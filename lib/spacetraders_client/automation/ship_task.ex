defmodule SpacetradersClient.Automation.ShipTask do
  use Ecto.Schema

  alias SpacetradersClient.Automation.DecisionFactor
  alias SpacetradersClient.Automation.ShipAutomationTick
  alias SpacetradersClient.Automation.ShipTaskFloatArg
  alias SpacetradersClient.Automation.ShipTaskStringArg
  alias SpacetradersClient.Automation.ShipTaskCondition
  alias SpacetradersClient.Utility

  import Ecto.Changeset

  schema "ship_tasks" do
    has_many :active_automation_ticks, ShipAutomationTick,
      foreign_key: :active_task_id,
      preload_order: [asc: :timestamp]

    field :name, :string
    field :utility, :float

    has_many :decision_factors, DecisionFactor
    has_many :float_args, ShipTaskFloatArg, on_replace: :delete_if_exists
    has_many :string_args, ShipTaskStringArg, on_replace: :delete_if_exists
    has_many :conditions, ShipTaskCondition, on_replace: :delete_if_exists
  end

  def from_legacy_task(task) do
    float_args =
      task.args
      |> Enum.filter(fn {_k, v} -> is_number(v) end)
      |> Enum.map(fn {k, v} -> %{name: to_string(k), value: v * 1.0} end)

    string_args =
      task.args
      |> Enum.filter(fn {_k, v} -> is_binary(v) || is_atom(v) end)
      |> Enum.map(fn {k, v} -> %{name: to_string(k), value: to_string(v)} end)

    conditions =
      Enum.map(task.conditions, fn c -> %{name: to_string(Function.info(c)[:name])} end)

    decision_factors =
      get_in(task, [Access.key(:utility), Access.key(:factors)])
      |> List.wrap()
      |> Enum.map(fn f ->
        %{
          name: to_string(f.name),
          input_value: f.input * 1.0,
          output_value: f.output * 1.0,
          weight: Map.get(f, :weight, 1.0) * 1.0
        }
      end)

    %__MODULE__{
      name: to_string(task.name),
      utility: if(task.utility, do: Utility.score(task.utility), else: 0.0)
    }
    |> change()
    |> put_assoc(:float_args, float_args)
    |> put_assoc(:string_args, string_args)
    |> put_assoc(:conditions, conditions)
    |> put_assoc(:decision_factors, decision_factors)
  end

  def start_time(%__MODULE__{} = task) do
    Enum.map(task.active_automation_ticks, fn tick -> tick.timestamp end)
    |> Enum.min(DateTime)
  end

  def args(%__MODULE__{} = task) do
    (task.float_args ++ task.string_args)
    |> Map.new(fn arg ->
      {arg.name, arg.value}
    end)
  end

  def arg(task, name) do
    task = change(task)

    float_args = get_field(task, :float_args, [])
    string_args = get_field(task, :string_args, [])

    if arg = Enum.find(float_args, fn a -> a.name == name end) do
      arg.value
    else
      if arg = Enum.find(string_args, fn a -> a.name == name end) do
        arg.value
      else
        nil
      end
    end
  end
end
