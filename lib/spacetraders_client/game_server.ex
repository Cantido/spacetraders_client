defmodule SpacetradersClient.GameServer do
  use GenServer

  alias SpacetradersClient.Client
  alias SpacetradersClient.Game

  def ensure_started(agent_symbol, token) do
    name = {:game, agent_symbol}

    if is_pid(:global.whereis_name(name)) do
      {:ok, :already_started}
    else
      DynamicSupervisor.start_child(
        SpacetradersClient.GameSupervisor,
        {__MODULE__, [token: token]}
      )
    end
  end

  def start_link(opts) do
    Keyword.fetch!(opts, :token)
    |> Client.new()
    |> Game.new()
    |> Game.load_agent()
    |> case do
      {:ok, game} ->
        opts = %{game: game}

        GenServer.start_link(__MODULE__, opts, name: {:global, {:game, game.agent["symbol"]}})

      err ->
        {:error, err}
    end
  end

  def init(opts) do
    Phoenix.PubSub.subscribe(SpacetradersClient.PubSub, "agent:" <> opts.game.agent["symbol"])

    {:ok, opts, {:continue, :load_game}}
  end

  def game(agent_symbol) do
    name = {:game, agent_symbol}

    if is_pid(:global.whereis_name(name)) do
      GenServer.call({:global, name}, :get_game, 20_000)
    else
      {:error, :agent_not_found}
    end
  end

  def reload(agent_symbol) do
    name = {:game, agent_symbol}

    if is_pid(:global.whereis_name(name)) do
      GenServer.call({:global, name}, :reload_game, 20_000)
    else
      {:error, :agent_not_found}
    end
  end

  def handle_call(:get_game, _from, state) do
    {:reply, {:ok, state.game}, state}
  end

  def handle_call(:reload_game, _from, state) do
    {:reply, :ok, state, {:continue, :load_game}}
  end

  def handle_continue(:load_game, state) do
    game =
      state.game
      |> Game.load_agent!()
      |> Game.load_fleet!()
      |> Game.load_all_waypoints!()
      |> Game.load_markets!()
      |> Game.load_shipyards!()
      |> Game.load_construction_sites!()

    {:noreply, %{state | game: game}}
  end

  def handle_info(_, state) do
    {:noreply, state}
  end
end
