defmodule SpacetradersClient.Automatons.HaulerShip do
  alias SpacetradersClient.Behaviors
  alias SpacetradersClient.Ship
  alias Taido.Node

  require Logger

  defstruct [
    :phase,
    :state,
    :tree,
    :behaviors
  ]

  def new(state) do
    phase = select_phase(state.ship, state.markets["X1-BU22-H54"])
    behaviors = behaviors()

    tree =
      behaviors[phase]
      |> Taido.start(state)

    %__MODULE__{
      phase: phase,
      state: state,
      tree: tree,
      behaviors: behaviors
    }
  end

  def tick(struct) do
    next_phase = select_phase(struct.state.ship, struct.state.markets["X1-BU22-H54"])

    next_struct =
      if struct.phase == next_phase do
        Logger.debug("Ship #{struct.state.ship["symbol"]} at phase #{struct.phase}")
        struct
      else
        transition_to(struct, next_phase)
      end

    {_result, new_tree} = Taido.tick(next_struct.tree)

    %{next_struct | tree: new_tree, state: new_tree.state}
  end

  def handle_message(struct, msg) do
    new_tree = Taido.handle_message(struct.tree, msg)

    %{struct | tree: new_tree}
  end

  def transition_to(struct, new_phase) do
    Logger.debug("Ship #{struct.state.ship["symbol"]} transitioning from #{struct.phase} to #{new_phase}")

    next_state = struct.tree.state

    _ = Taido.terminate(struct.tree)

    tree =
      Map.fetch!(struct.behaviors, new_phase)
      |> Taido.start(next_state)

    %{struct | tree: tree, phase: new_phase}
  end

  defp select_phase(ship, market) do
    cond do
      Enum.any?(Ship.cargo_to_jettison(ship, market)) ->
        :jettison
      ship["nav"]["waypointSymbol"] == "X1-BU22-H54" && ship["cargo"]["units"] > 0 ->
        :selling
      ship["cargo"]["units"] < ship["cargo"]["capacity"] - 3 ->
        :loading
      true ->
        :selling
    end
  end

  defp behaviors do
    loading_behavior =
      Behaviors.travel_to_waypoint("X1-BU22-DA5F")

    selling_behavior = Node.sequence([
      Behaviors.travel_to_waypoint("X1-BU22-H54"),
      Behaviors.wait_for_transit(),
      Behaviors.dock_ship(),
      Behaviors.sell_cargo_item()
    ])

    jettison_behavior =
      Node.sequence([
        Behaviors.enter_orbit(),
        Behaviors.jettison_cargo()
      ])

    %{
      loading: loading_behavior,
      selling: selling_behavior,
      jettison: jettison_behavior
    }
  end
end
