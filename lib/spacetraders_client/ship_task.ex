defmodule SpacetradersClient.ShipTask do
  alias SpacetradersClient.Utility

  @enforce_keys [
    :id,
    :name
  ]
  defstruct [
    :id,
    :name,
    :utility,
    args: %{},
    conditions: [],
  ]

  def new(name, args \\ %{}, conditions \\ []) do
    %__MODULE__{
      id: Uniq.UUID.uuid7(),
      name: name,
      args: args,
      conditions: conditions
    }
  end

  def meets_conditions?(%__MODULE__{conditions: conditions},  ship) do
    Enum.all?(conditions, fn condition ->
      condition.(ship)
    end)
  end

  def utility_score(%__MODULE__{} = task) do
    Utility.score(task.utility)
  end

  def put_utility(%__MODULE__{} = task, utility) do
    %{task | utility: utility}
  end

  def assign(%__MODULE__{} = task, key, value) do
    put_in(task, [Access.key(:args), key], value)
  end

  def assign(%__MODULE__{} = task, assigns) when is_map(assigns) do
    update_args(task, fn args ->
      Map.merge(args, assigns)
    end)
  end

  def update_args(%__MODULE__{} = task, update_fun) do
    update_in(task, [Access.key(:args)], update_fun)
  end

  def add_condition(%__MODULE__{} = task, condition_fun) do
    update_in(task, [Access.key(:conditions)], fn conditions ->
      [condition_fun | conditions]
    end)
  end

  defp regenerate_id(%__MODULE__{} = task) do
    put_in(task, [Access.key(:id)], Uniq.UUID.uuid7())
  end

  def variation(task, key_or_assigns, value_or_conditions \\ [])

  def variation(%__MODULE__{} = task, args, conditions) when is_map(args) and is_list(conditions) do
    assign(task, args)
    |> regenerate_id()
  end

  def variation(%__MODULE__{} = task, key, value) when is_atom(key) do
    assign(task, key, value)
    |> regenerate_id()
  end

end
