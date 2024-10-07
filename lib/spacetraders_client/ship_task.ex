defmodule SpacetradersClient.ShipTask do
  defstruct [
    :name,
    args: %{},
    conditions: []
  ]

  def new(name, args \\ %{}, conditions \\ []) do
    %__MODULE__{
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
end
