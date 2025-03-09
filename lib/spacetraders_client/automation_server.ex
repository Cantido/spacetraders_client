defmodule SpacetradersClient.AutomationServer do
  use GenServer

  alias SpacetradersClient.AgentAutomaton
  alias SpacetradersClient.Client
  alias SpacetradersClient.Agents
  alias SpacetradersClient.Game

  alias Phoenix.PubSub

  require Logger

  @pubsub SpacetradersClient.PubSub

  def start_link(_opts \\ []) do
    token = System.fetch_env!("SPACETRADERS_TOKEN")
    client = Client.new(token)

    case Agents.my_agent(client) do
      {:ok, %{status: 200, body: body}} ->
        callsign = body["data"]["symbol"]

        opts = [token: token]

        GenServer.start_link(__MODULE__, opts, name: {:global, callsign})

      err ->
        {:error, err}
    end
  end

  def init(opts) do
    token = Keyword.fetch!(opts, :token)
    client = SpacetradersClient.Client.new(token)

    {:ok, %{client: client}, {:continue, :load_data}}
  end

  def current_task(callsign, ship_symbol) do
    if is_pid(:global.whereis_name(callsign)) do
      GenServer.call({:global, callsign}, {:get_task, ship_symbol}, 20_000)
    else
      {:error, :callsign_not_found}
    end
  end

  def automaton(callsign, ship_symbol) do
    if is_pid(:global.whereis_name(callsign)) do
      GenServer.call({:global, callsign}, {:get_automaton, ship_symbol}, 20_000)
    else
      {:error, :callsign_not_found}
    end
  end

  def automaton(callsign) do
    if is_pid(:global.whereis_name(callsign)) do
      GenServer.call({:global, callsign}, :get_automaton, 20_000)
    else
      {:error, :callsign_not_found}
    end
  end

  def handle_call({:get_task, ship_symbol}, _from, state) do
    if automaton = Map.get(state.automaton.ship_automata, ship_symbol) do
      {:reply, {:ok, automaton.current_action}, state}
    else
      {:reply, {:error, :ship_not_found}, state}
    end
  end

  def handle_call({:get_automaton, ship_symbol}, _from, state) do
    if automaton = Map.get(state.automaton.ship_automata, ship_symbol) do
      {:reply, {:ok, automaton}, state}
    else
      {:reply, {:error, :ship_not_found}, state}
    end
  end

  def handle_call(:get_automaton, _from, state) do
    {:reply, {:ok, state.automaton}, state}
  end

  def handle_continue(:load_data, state) do
    {:noreply, load_game(state), {:continue, :start_automation}}
  end

  def handle_continue(:start_automation, state) do
    state = assign_automatons(state)

    Logger.debug("Initialized automation server")

    PubSub.broadcast(@pubsub, "agent:#{state.game_state.agent["symbol"]}", {:automation_started, state.automaton})

    timer = Process.send_after(self(), :reload_game, :timer.minutes(5))

    {:noreply, Map.put(state, :reload_timer, timer), {:continue, :schedule_tick}}
  end

  def handle_continue(:schedule_tick, state) do
    timer = Process.send_after(self(), :tick_behaviors, :timer.seconds(15))

    {:noreply, Map.put(state, :timer, timer)}
  end

  def handle_continue(:schedule_reload, state) do
    timer = Process.send_after(self(), :reload_game, :timer.minutes(15))

    {:noreply, Map.put(state, :reload_timer, timer)}
  end

  def handle_info(:tick_behaviors, state) do
    {automaton, game_state} = AgentAutomaton.tick(state.automaton, state.game_state)

    PubSub.broadcast(@pubsub, "agent:#{state.game_state.agent["symbol"]}", {:automaton_updated, automaton})

    state =
      state
      |> Map.put(:automaton, automaton)
      |> Map.put(:game_state, game_state)

    {:noreply, state, {:continue, :schedule_tick}}
  end

  def handle_info(:fleet_updated, state) do
    state =
      state
      |> update_in([:game_state], &Game.load_fleet!/1)
      |> assign_automatons()

    {:noreply, state}
  end

  def handle_info(:reload_game, state) do
    state =
      state
      |> load_game()
      |> assign_automatons()

    {:noreply, state, {:continue, :schedule_reload}}
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end

  defp load_game(state) do
    game_state =
      Game.new(state.client)
      |> Game.load_agent!()
      |> Game.load_fleet!()
      |> Game.load_all_waypoints!()
      |> Game.load_markets!()
      |> Game.load_shipyards!()
      |> Game.load_construction_sites!()
      |> Game.start_ledger()

    Phoenix.PubSub.subscribe(SpacetradersClient.PubSub, "agent:" <> game_state.agent["symbol"])

    Map.put(state, :game_state, game_state)
  end

  defp assign_automatons(state) do
    automaton = AgentAutomaton.new(state.game_state)

    Map.put(state, :automaton, automaton)
  end
end
