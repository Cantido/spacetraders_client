defmodule SpacetradersClient.AutomationServer do
  use GenServer

  alias SpacetradersClient.AgentAutomaton
  alias SpacetradersClient.Client
  alias SpacetradersClient.Agents
  alias SpacetradersClient.Game.Agent
  alias SpacetradersClient.Repo

  import Ecto.Query

  require Logger

  @interval 15_000

  def start_link(opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def init(opts) do
    {:ok, %{automata: %{}}, 0}
  end

  def handle_info(:timeout, state) do
    continuing_automata =
      Repo.all(
        from a in Agent,
          where: [automation_enabled: false]
      )
      |> Enum.reduce(state.automata, fn disabled_agent, automata ->
        if automaton = Map.get(automata, disabled_agent.symbol) do
          AgentAutomaton.terminate(automaton)
        end

        Map.delete(automata, disabled_agent.symbol)
      end)

    continuing_automata_ids = Map.keys(continuing_automata)

    new_automata =
      Repo.all(
        from a in Agent,
          where: [automation_enabled: true],
          where: a.symbol not in ^continuing_automata_ids
      )
      |> Map.new(fn agent ->
        {agent.symbol, AgentAutomaton.new(agent.symbol)}
      end)

    automata =
      new_automata
      |> Map.merge(continuing_automata)
      |> tap(fn automata ->
        if Enum.count(automata) > 0 do
          Logger.info("AutomationServer ticking automata")
        end
      end)
      |> Map.new(fn {agent_symbol, automaton} ->
        agent = Repo.get_by!(Agent, symbol: agent_symbol)
        client = Client.new(agent.token)

        automaton = AgentAutomaton.tick(automaton, client)

        {agent_symbol, automaton}
      end)

    {:noreply, %{automata: automata}, @interval}
  end
end
