defmodule SpacetradersClient.ShipAutomaton do
  alias SpacetradersClient.Game
  require Logger

  @enforce_keys [
    :ship_symbol,
    :phase,
    :tree,
    :behavior_fun,
    :state_fun
  ]
  defstruct [
    :ship_symbol,
    :phase,
    :tree,
    :behavior_fun,
    :state_fun
  ]

  def new(%Game{} = game, ship_symbol, task_fun, behavior_fun) when is_binary(ship_symbol) and is_function(task_fun, 2) and is_function(behavior_fun, 1) do
    task = task_fun.(game, ship_symbol)

    tree =
      if task do
        behavior_fun.(task)
      end

    %__MODULE__{
      ship_symbol: ship_symbol,
      phase: task,
      tree: tree,
      behavior_fun: behavior_fun,
      state_fun: task_fun
    }
  end

  def tick(%__MODULE__{} = struct, %Game{} = game) do
    next_task = struct.state_fun.(game, struct.ship_symbol)

    # yes I wrote Taido to maintain its own state,
    # but I realized I need it coordinated somewhere...

    if next_task do
      struct =
        if struct.phase == next_task do
          Logger.debug("Ship #{struct.ship_symbol} at phase #{inspect struct.phase.name}")
          struct
        else
          transition_to(struct, next_task)
        end

      {_result, tree, %{game: game}} = Taido.BehaviorTree.tick(struct.tree, %{ship_symbol: struct.ship_symbol, game: game})

      {%{struct | tree: tree}, game}
    else
      {struct, game}
    end
  end

  defp transition_to(%__MODULE__{} = struct, next_action) do
    Logger.debug("Ship #{struct.ship_symbol} performing #{inspect next_action.name}")

    if struct.tree do
      _ = Taido.BehaviorTree.terminate(struct.tree)
    end

    tree = struct.behavior_fun.(next_action)

    %{struct | tree: tree, phase: next_action}
  end

  def handle_message(%__MODULE__{} = struct, msg) do
    new_tree = Taido.BehaviorTree.handle_message(struct.tree, msg)

    %{struct | tree: new_tree}
  end
end
