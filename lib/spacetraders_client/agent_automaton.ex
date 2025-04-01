defmodule SpacetradersClient.AgentAutomaton do
  alias SpacetradersClient.ShipAutomaton
  alias SpacetradersClient.Game.Ship
  alias SpacetradersClient.Repo

  import Ecto.Query

  require Logger

  defstruct ship_automata: %{}

  def new(agent_symbol) do
    automata =
      from(s in Ship, where: [agent_symbol: ^agent_symbol])
      |> Repo.all()
      |> Enum.map(fn ship ->
        automaton = ShipAutomaton.new(ship)

        {ship.symbol, automaton}
      end)
      |> Enum.reject(fn {_symbol, automaton} -> is_nil(automaton) end)
      |> Map.new()

    %__MODULE__{
      ship_automata: automata
    }
  end

  def tick(%__MODULE__{} = struct, client) do
    Enum.reduce(struct.ship_automata, struct, fn {ship_symbol, automaton}, struct ->
      automaton = ShipAutomaton.tick(automaton, client)

      struct =
        struct
        |> Map.update!(:ship_automata, fn automata ->
          Map.put(automata, ship_symbol, automaton)
        end)

      struct
    end)
  end

  def terminate(%__MODULE__{} = struct) do
    Enum.each(struct.ship_automata, fn {_symbol, automaton} ->
      ShipAutomaton.terminate(automaton)
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
