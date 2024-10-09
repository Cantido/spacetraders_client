defmodule SpacetradersClient.Automata do

  alias SpacetradersClient.ShipAutomaton

  require Logger

  def for_ship(ship) do
    case ship["registration"]["role"] do
      "EXCAVATOR" ->
        ShipAutomaton.new(ship["symbol"])
      "COMMAND" ->
        ShipAutomaton.new(ship["symbol"])
      "TRANSPORT" ->
        ShipAutomaton.new(ship["symbol"])
      "HAULER" ->
        ShipAutomaton.new(ship["symbol"])
      _ ->
        nil
    end
  end
end
