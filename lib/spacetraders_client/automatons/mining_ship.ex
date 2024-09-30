defmodule SpacetradersClient.Automatons.MiningShip do
  alias SpacetradersClient.Behaviors
  alias SpacetradersClient.Game
  alias SpacetradersClient.Ship
  alias Taido.Node

  require Logger

  defstruct [
    :ship_symbol,
    :phase,
    :tree,
    :behaviors
  ]


  def new(%Game{} = game, ship_symbol) do
    ship = Game.ship(game, ship_symbol)

    phase = select_phase(ship, Game.market(game, "X1-BU22", "X1-BU22-H54"))
    behaviors = behaviors()

    tree =
      behaviors[phase]
      |> Taido.start(%{ship_symbol: ship_symbol, game: game})

    %__MODULE__{
      ship_symbol: ship_symbol,
      phase: phase,
      tree: tree,
      behaviors: behaviors
    }
  end

  def tick(%__MODULE__{} = struct, game) do
    ship = Game.ship(game, struct.ship_symbol)

    next_phase = select_phase(ship, Game.market(game, "X1-BU22", "X1-BU22-H54"))

    next_struct =
      if struct.phase == next_phase do
        Logger.debug("Ship #{struct.ship_symbol} at phase #{struct.phase}")
        struct
      else
        transition_to(struct, next_phase, game)
      end

    # yes I wrote Taido to maintain its own state,
    # but I realized I need it coordinated somewhere...

    tree =
      Map.put(next_struct.tree, :game, game)

    {_result, new_tree} = Taido.tick(tree)

    %{next_struct | tree: new_tree}
  end

  def game(%__MODULE__{} = struct) do
    struct.tree.state.game
  end

  def handle_message(struct, msg) do
    new_tree = Taido.handle_message(struct.tree, msg)

    %{struct | tree: new_tree}
  end

  def transition_to(%__MODULE__{} = struct, new_phase, game) do
    Logger.debug("Ship #{struct.ship_symbol} transitioning from #{struct.phase} to #{new_phase}")

    _ = Taido.terminate(struct.tree)

    tree =
      Map.fetch!(struct.behaviors, new_phase)
      |> Taido.start(%{ship_symbol: struct.ship_symbol, game: game})

    %{struct | tree: tree, phase: new_phase}
  end

  defp select_phase(ship, market) do
    cond do
      ship["nav"]["waypointSymbol"] == "X1-BU22-H54" && ship["cargo"]["units"] == 0 ->
        :mining
      ship["nav"]["waypointSymbol"] == "X1-BU22-DA5F" && ship["cargo"]["units"] < ship["cargo"]["capacity"] - 2 ->
        :mining
      Enum.any?(Ship.cargo_to_jettison(ship, market)) ->
        :jettison
      Ship.has_saleable_cargo?(ship, market) ->
        :selling
      true ->
        :mining
    end
  end

  defp behaviors do
    mining_behavior =
      Node.sequence([
        Behaviors.travel_to_waypoint("X1-BU22-DA5F"),
        Behaviors.wait_for_transit(),
        Behaviors.wait_for_ship_cooldown(),
        Behaviors.extract_resources()
      ])

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
      mining: mining_behavior,
      selling: selling_behavior,
      jettison: jettison_behavior
    }
  end
end
