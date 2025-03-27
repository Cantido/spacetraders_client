defmodule SpacetradersClient.AutomationServer do
  use GenServer

  alias SpacetradersClient.AgentAutomaton
  alias SpacetradersClient.Client
  alias SpacetradersClient.Agents
  alias SpacetradersClient.Game
  alias SpacetradersClient.GameServer

  alias Phoenix.PubSub

  require Logger

  @pubsub SpacetradersClient.PubSub

  def start_link(opts) do
    token = Keyword.fetch!(opts, :token)
    client = Client.new(token)

    case Agents.my_agent(client) do
      {:ok, %{status: 200, body: body}} ->
        callsign = body["data"]["symbol"]

        opts = [token: token, callsign: callsign]

        GenServer.start_link(__MODULE__, opts, name: {:global, callsign})

      err ->
        {:error, err}
    end
  end

  def init(opts) do
    token = Keyword.fetch!(opts, :token)
    client = SpacetradersClient.Client.new(token)
    callsign = Keyword.fetch!(opts, :callsign)

    {:ok, _} = GameServer.ensure_started(callsign, token)

    PubSub.broadcast(
      @pubsub,
      "agent:#{callsign}",
      {:automation_starting, callsign}
    )

    {:ok, %{client: client, agent_symbol: callsign}, {:continue, :start_automation}}
  end

  def stop(callsign) do
    if is_pid(:global.whereis_name(callsign)) do
      GenServer.stop({:global, callsign})
    else
      {:error, :callsign_not_found}
    end
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

  def handle_continue(:start_automation, state) do
    state = assign_automatons(state)

    Logger.debug("Initialized automation server")

    PubSub.broadcast(
      @pubsub,
      "agent:#{state.agent_symbol}",
      {:automation_started, state.automaton}
    )

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
    {:ok, game_state} = GameServer.game(state.agent_symbol)
    {automaton, game_state} = AgentAutomaton.tick(state.automaton, game_state)

    PubSub.broadcast(
      @pubsub,
      "agent:#{state.agent_symbol}",
      {:automaton_updated, automaton}
    )

    state =
      state
      |> Map.put(:automaton, automaton)

    {:noreply, state, {:continue, :schedule_tick}}
  end

  def handle_info(:reload_game, state) do
    state =
      state
      |> load_game()
      |> assign_automatons()

    {:noreply, state, {:continue, :schedule_reload}}
  end

  def handle_info(msg, state) do
    Logger.warning("Automation server received unknown info message: #{inspect msg}")
    {:noreply, state}
  end

  defp load_game(state) do
    :ok = GameServer.reload(state.agent_symbol)

    state
  end

  defp assign_automatons(state) do
    automaton = AgentAutomaton.new(state.game_state)

    Map.put(state, :automaton, automaton)
  end

  def terminate(_, state) do
    PubSub.broadcast(
      @pubsub,
      "agent:#{state.agent_symbol}",
      {:automation_stopped, state.automaton}
    )

    :ok
  end
end
