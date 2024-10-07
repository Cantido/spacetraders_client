defmodule SpacetradersClient.AutomationServer do
  use GenServer

  alias SpacetradersClient.AgentAutomaton
  alias SpacetradersClient.Client
  alias SpacetradersClient.Agents
  alias SpacetradersClient.Game
  alias SpacetradersClient.Automata
  alias SpacetradersClient.ShipAutomaton

  require Logger

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

    if :ets.whereis(:ledgers) == :undefined do
      :ets.new(:ledgers, [:named_table, :public, write_concurrency: true, read_concurrency: true])
    end

    {:ok, %{client: client}, {:continue, :load_data}}
  end

  def current_task(callsign, ship_symbol) do
    if is_pid(:global.whereis_name(callsign)) do
      GenServer.call({:global, callsign}, {:get_task, ship_symbol}, 20_000)
    else
      {:error, :callsign_not_found}
    end
  end

  def transactions(callsign, opts \\ []) do
    if GenServer.whereis({:global, callsign}) do
      if since = Keyword.get(opts, :since) do
        GenServer.call({:global, callsign}, {:get_transactions, since}, 20_000)
      else
        GenServer.call({:global, callsign}, :get_transactions, 20_000)
      end
    else
      {:error, :agent_not_found}
    end
  end

  def ledger(callsign) do
    if is_pid(:global.whereis_name(callsign)) do
      GenServer.call({:global, callsign}, :get_ledger, 20_000)
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

  def handle_call(:get_ledger, _from, state) do
    {:reply, {:ok, state.game_state.ledger}, state}
  end

  def handle_call(:get_transactions, _from, state) do
    {:reply, {:ok, state.game_state.transactions}, state}
  end

  def handle_call({:get_transactions, since}, _from, state) do
    transactions =
      state.game_state.transactions
      |> Enum.filter(fn txn ->
        {:ok, ts, _} = DateTime.from_iso8601(txn["timestamp"])
        DateTime.after?(ts, since)
      end)
    {:reply, {:ok, transactions}, state}
  end

  def handle_continue(:load_data, state) do
    {:noreply, load_game(state), {:continue, :start_automation}}
  end

  def handle_continue(:start_automation, state) do
    state = assign_automatons(state)

    Logger.debug("Initialized automation server")

    timer = Process.send_after(self(), :reload_game, :timer.minutes(5))

    {:noreply, Map.put(state, :reload_timer, timer), {:continue, :schedule_tick}}
  end

  def handle_continue(:schedule_tick, state) do
    timer = Process.send_after(self(), :tick_behaviors, :timer.seconds(15))

    {:noreply, Map.put(state, :timer, timer)}
  end

  def handle_continue(:schedule_reload, state) do
    timer = Process.send_after(self(), :reload_game, :timer.minutes(5))

    {:noreply, Map.put(state, :reload_timer, timer)}
  end

  def handle_info(:tick_behaviors, state) do
    {automaton, game_state} = AgentAutomaton.tick(state.automaton, state.game_state)

    state =
      state
      |> Map.put(:automaton, automaton)
      |> Map.put(:game_state, game_state)

    record = {state.game_state.agent["symbol"], game_state.ledger}
    :ets.insert(:ledgers, record)

    {:noreply, state, {:continue, :schedule_tick}}
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
      |> Game.load_fleet_waypoints!()
      |> Game.load_markets!()

    game_state =
      if state[:game_state] do
        txns = state.game_state.transactions
        ledger = state.game_state.ledger

        game_state
        |> Map.put(:transactions, txns)
        |> Map.put(:ledger, ledger)
      else
        game_state
      end

    game_state =
      case :ets.lookup(:ledgers, game_state.agent["symbol"]) do
        [] ->
          game_state
        [{_symbol, ledger}] ->
          Map.put(game_state, :ledger, ledger)
      end

    Map.put(state, :game_state, game_state)
  end

  defp assign_automatons(state) do
    automaton = AgentAutomaton.new(state.game_state)

    Map.put(state, :automaton, automaton)
  end
end
