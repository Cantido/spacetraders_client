defmodule SpacetradersClient.AutomationServer do
  use GenServer

  alias SpacetradersClient.Client
  alias SpacetradersClient.Agents
  alias SpacetradersClient.Game
  alias SpacetradersClient.Automatons
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

    {:ok, %{client: client}, {:continue, :load_data}}
  end

  def current_task(callsign, ship_symbol) do
    if is_pid(:global.whereis_name(callsign)) do
      GenServer.call({:global, callsign}, {:get_task, ship_symbol}, 10_000)
    else
      {:error, :callsign_not_found}
    end
  end

  def handle_call({:get_task, ship_symbol}, _from, state) do
    if automaton = Map.get(state.automatons, ship_symbol) do
      {:reply, {:ok, automaton.phase}, state}
    else
      {:reply, {:error, :ship_not_found}, state}
    end
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
    timer = Process.send_after(self(), :tick_behaviors, :timer.seconds(10))

    {:noreply, Map.put(state, :timer, timer)}
  end

  def handle_continue(:schedule_reload, state) do
    timer = Process.send_after(self(), :reload_game, :timer.minutes(5))

    {:noreply, Map.put(state, :reload_timer, timer)}
  end

  def handle_info(:tick_behaviors, state) do
    state =
      Enum.reduce(state.automatons, state, fn {ship_symbol, automaton}, state ->
        {automaton, game_state} = ShipAutomaton.tick(automaton, state.game_state)

        state
        |> Map.update!(:automatons, fn automatons ->
          Map.put(automatons, ship_symbol, automaton)
        end)
        |> Map.put(:game_state, game_state)
      end)

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
    automatons =
      Map.new(state.automatons, fn {ship_symbol, automaton} ->
        new_automaton = ShipAutomaton.handle_message(automaton, msg)

        {ship_symbol, new_automaton}
      end)

    state = Map.put(state, :automatons, automatons)

    {:noreply, state}
  end

  defp load_game(state) do
    game_state =
      Game.new(state.client)
      |> Game.load_agent!()
      |> Game.load_fleet!()
      |> Game.load_fleet_waypoints!()
      |> Game.load_markets!()

    Map.put(state, :game_state, game_state)
  end

  defp assign_automatons(state) do
    automatons =
      state.game_state.fleet
      |> Enum.map(fn {ship_symbol, ship} ->
        automaton =
          case ship["registration"]["role"] do
            "EXCAVATOR" ->
              Automatons.mining_ship(state.game_state, ship_symbol)
            "COMMAND" ->
              Automatons.trading_ship(state.game_state, ship_symbol)
            "TRANSPORT" ->
              Automatons.trading_ship(state.game_state, ship_symbol)
            # "SURVEYOR" ->
            #   Automatons.surveyor_ship(state.game_state, ship_symbol)
            _ ->
              nil
          end

        {ship_symbol, automaton}
      end)
      |> Enum.reject(fn {_symbol, automaton} -> is_nil(automaton) end)
      |> Map.new()

    Map.put(state, :automatons, automatons)
  end
end
