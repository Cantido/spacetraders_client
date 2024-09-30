defmodule SpacetradersClient.AutomationServer do
  use GenServer

  alias SpacetradersClient.Agents
  alias SpacetradersClient.Game
  alias SpacetradersClient.Systems
  alias SpacetradersClient.Fleet
  alias SpacetradersClient.Automatons.MiningShip

  require Logger

  def start_link do
    GenServer.start_link(__MODULE__, [])
  end

  def init(_opts) do
    token = System.fetch_env!("SPACETRADERS_TOKEN")
    client = SpacetradersClient.Client.new(token)

    {:ok, %{client: client}, {:continue, :load_data}}
  end

  def handle_continue(:load_data, state) do
    game_state =
      Game.new(state.client)
      |> Game.load_agent!()
      |> Game.load_fleet!()
      |> Game.load_fleet_waypoints!()
      |> Game.load_markets!()

    {:noreply, Map.put(state, :game_state, game_state), {:continue, :start_automation}}
  end

  def handle_continue(:start_automation, state) do
    game = Game.load_market!(state.game_state, "X1-BU22", "X1-BU22-H54")
    state = Map.put(state, :game_state, game)

    automatons =
      state.game_state.fleet
      |> Enum.filter(fn {_ship_symbol, ship} -> ship["registration"]["role"] == "EXCAVATOR" end)
      # |> Enum.filter(fn ship -> ship["symbol"] == "C0SM1C_R05E-3" end)
      |> Map.new(fn {ship_symbol, _ship} ->
        automaton =
          MiningShip.new(state.game_state, ship_symbol)

        {ship_symbol, automaton}
      end)

    state =
      Map.merge(state, %{automatons: automatons})

    Logger.debug("Initialized automation server")

    {:noreply, state, {:continue, :schedule_tick}}
  end

  def handle_continue(:schedule_tick, state) do
    timer = Process.send_after(self(), :tick_behaviors, :timer.seconds(10))

    {:noreply, Map.put(state, :timer, timer)}
  end

  def handle_info(:tick_behaviors, state) do
    state =
      Enum.reduce(state.automatons, state, fn {ship_symbol, automaton}, state ->
        new_automaton = MiningShip.tick(automaton, state.game_state)

        state
        |> Map.update!(:automatons, fn automatons ->
          Map.put(automatons, ship_symbol, new_automaton)
        end)
        |> Map.put(:game_state, MiningShip.game(new_automaton))
      end)

    {:noreply, state, {:continue, :schedule_tick}}
  end

  def handle_info(msg, state) do
    automatons =
      Map.new(state.automatons, fn {ship_symbol, automaton} ->
        new_automaton = MiningShip.handle_message(automaton, msg)

        {ship_symbol, new_automaton}
      end)

    {:noreply, Map.put(state, :automatons, automatons)}
  end
end
