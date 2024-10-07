defmodule SpacetradersClient.Automata do

  alias SpacetradersClient.ShipAutomaton

  require Logger

  def for_ship(ship) do
    case ship["registration"]["role"] do
      "EXCAVATOR" ->
        ShipAutomaton.new(ship["symbol"], fn _, _ -> [] end)
      "COMMAND" ->
        ShipAutomaton.new(ship["symbol"], fn _, _ -> [] end)
      "TRANSPORT" ->
        ShipAutomaton.new(ship["symbol"], fn _, _ -> [] end)
      "HAULER" ->
        ShipAutomaton.new(ship["symbol"], fn _, _ -> [] end)
      _ ->
        nil
    end
  end
end
