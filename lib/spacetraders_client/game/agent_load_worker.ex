defmodule SpacetradersClient.Game.AgentLoadWorker do
  use Oban.Worker,
    queue: :api,
    unique: [
      period: {5, :minutes},
      fields: [:worker, :args]
    ]

  alias SpacetradersClient.Game
  alias Phoenix.PubSub
  alias SpacetradersClient.Agents
  alias SpacetradersClient.Client
  alias SpacetradersClient.Fleet
  alias SpacetradersClient.Systems
  alias SpacetradersClient.Game.Agent
  alias SpacetradersClient.Game.Item
  alias SpacetradersClient.Game.Ship
  alias SpacetradersClient.Game.System
  alias SpacetradersClient.Game.ShipCargoItem
  alias SpacetradersClient.Game.Waypoint
  alias SpacetradersClient.Repo

  import Ecto.Query

  require Logger

  @pubsub SpacetradersClient.PubSub

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    agent = Repo.one(Agent)
    token = agent.token
    client = Client.new(token)
    topic = args["topic"]

    {:ok, %{status: 200, body: agent_body}} = Agents.my_agent(client)

    Logger.info("Loading data for agent #{agent_body["symbol"]}")

    agent =
      if agent = Repo.get_by(Agent, symbol: agent_body["data"]["symbol"]) do
        agent
      else
        %Agent{token: token}
      end
      |> Agent.changeset(agent_body["data"])
      |> Repo.insert_or_update!(conflict_target: :symbol, on_conflict: {:replace, [:credits]})

    ship_data =
      Stream.iterate(1, &(&1 + 1))
      |> Stream.map(fn page ->
        Fleet.list_ships(client, page: page)
      end)
      |> Stream.map(fn page ->
        {:ok, %{body: body, status: 200}} = page

        body
      end)
      |> Enum.reduce_while([], fn page, fleet ->
        new_fleet = page["data"] ++ fleet

        if page["meta"]["total"] == Enum.count(new_fleet) do
          {:halt, new_fleet}
        else
          {:cont, new_fleet}
        end
      end)

    ships_count = Enum.count(ship_data)

    system_ships =
      Enum.group_by(ship_data, fn ship ->
        ship["nav"]["systemSymbol"]
      end)

    system_ships
    |> Task.async_stream(
      fn {system_symbol, ships_in_system} ->
        if !Repo.exists?(from s in System, where: [symbol: ^system_symbol]) do
          {:ok, %{body: body, status: 200}} = Systems.get_system(client, system_symbol)

          %System{symbol: body["data"]["symbol"]}
          |> System.changeset(body["data"])
          |> Repo.insert!(conflict_target: :symbol, on_conflict: :nothing)
        end

        Enum.each(ships_in_system, fn ship_data ->
          Game.save_ship!(agent.symbol, ship_data)
        end)

        Enum.count(ships_in_system)
      end,
      timeout: 120_000
    )
    |> Stream.map(fn {:ok, count} -> count end)
    |> Stream.scan(&(&1 + &2))
    |> Enum.each(fn ships_loaded_count ->
      if is_binary(topic) do
        PubSub.broadcast!(
          @pubsub,
          topic,
          {:data_loaded, :fleet, ships_loaded_count, ships_count}
        )
      end
    end)

    Map.keys(system_ships)
    |> Task.async_stream(
      fn system_symbol ->
        Game.load_waypoints!(client, system_symbol, topic)
      end,
      timeout: 120_000
    )
    |> Stream.flat_map(fn {:ok, wps} -> wps end)
    |> Task.async_stream(
      fn waypoint ->
        waypoint = Repo.preload(waypoint, [:traits, :system])

        if Enum.any?(waypoint.traits, fn t -> t.symbol == "MARKETPLACE" end) do
          Game.load_market!(client, waypoint.system.symbol, waypoint.symbol, topic)
        end

        if Enum.any?(waypoint.traits, fn t -> t.symbol == "SHIPYARD" end) do
          Game.load_shipyard!(client, waypoint.system.symbol, waypoint.symbol, topic)
        end

        if waypoint.under_construction do
          Game.load_construction_site!(client, waypoint.system.symbol, waypoint.symbol, topic)
        end
      end,
      timeout: 120_000
    )
    |> Stream.run()

    SpacetradersClient.Finance.open_accounts(agent.symbol)

    :ok
  end
end
