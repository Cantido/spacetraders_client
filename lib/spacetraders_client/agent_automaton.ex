defmodule SpacetradersClient.AgentAutomaton do
  alias SpacetradersClient.ShipAutomaton
  alias SpacetradersClient.Automata
  alias SpacetradersClient.Game

  require Logger

  defstruct [
    ship_automata: %{}
  ]

  def new(%Game{} = game) do
    automata =
      game.fleet
      |> Enum.map(fn {ship_symbol, ship} ->
        automaton = Automata.for_ship(ship)

        {ship_symbol, automaton}
      end)
      |> Enum.reject(fn {_symbol, automaton} -> is_nil(automaton) end)
      |> Map.new()

    %__MODULE__{
      ship_automata: automata
    }
  end

  def tick(%__MODULE__{} = struct, %Game{} = game) do
    Enum.reduce(struct.ship_automata, {struct, game}, fn {ship_symbol, automaton}, {struct, game} ->
      {automaton, game} = ShipAutomaton.tick(automaton, game)

      struct =
        struct
        |> Map.update!(:ship_automata, fn automata ->
          Map.put(automata, ship_symbol, automaton)
        end)

      {struct, game}
    end)
  end

  def handle_message(%__MODULE__{} = struct, msg) do
    automata =
      Map.new(struct.ship_automata, fn {ship_symbol, automaton} ->
        new_automaton = ShipAutomaton.handle_message(automaton, msg)

        {ship_symbol, new_automaton}
      end)
    %{struct | ship_automata: automata}
  end
end
