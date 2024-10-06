defmodule SpacetradersClient.ShipAutomaton do
  alias SpacetradersClient.Behaviors
  alias SpacetradersClient.Game
  require Logger

  @enforce_keys [
    :ship_symbol,
    :tree,
    :current_action,
    :state_fun
  ]
  defstruct [
    :ship_symbol,
    :tree,
    :current_action,
    :state_fun
  ]

  def new(%Game{} = game, ship_symbol, task_fun) when is_binary(ship_symbol) and is_function(task_fun, 2) do
    task = task_fun.(game, ship_symbol)

    tree =
      if task do
        Behaviors.for_task(task)
      end

    %__MODULE__{
      ship_symbol: ship_symbol,
      tree: tree,
      state_fun: task_fun,
      current_action: task
    }
  end

  def tick(%__MODULE__{} = struct, %Game{} = game) do
    {result, tree, %{game: game}} = Taido.BehaviorTree.tick(struct.tree, %{ship_symbol: struct.ship_symbol, game: game})

    Logger.debug("Automaton for #{struct.ship_symbol} returned #{result} for task #{struct.current_action.name}")

    case result do
      :running ->
        {%{struct | tree: tree}, game}

      _ ->
        if struct.tree do
          _ = Taido.BehaviorTree.terminate(struct.tree)
        end

        next_task = struct.state_fun.(game, struct.ship_symbol)

        tree = Behaviors.for_task(next_task)

        {%{struct | tree: tree, current_action: next_task}, game}
    end
  end

  def handle_message(%__MODULE__{} = struct, msg) do
    new_tree = Taido.BehaviorTree.handle_message(struct.tree, msg)

    %{struct | tree: new_tree}
  end
end
