defmodule SpacetradersClientWeb.SystemLive do
  use SpacetradersClientWeb, :live_view

  alias Phoenix.LiveView.AsyncResult
  alias Phoenix.PubSub
  alias SpacetradersClient.AutomationServer
  alias SpacetradersClient.Agents
  alias SpacetradersClient.Fleet
  alias SpacetradersClient.Systems
  alias SpacetradersClient.Client

  @pubsub SpacetradersClient.PubSub

  def render(assigns) do
    ~H"""
    <.live_component
      module={SpacetradersClientWeb.OrbitalsMenuComponent}
      id="orbitals"
      client={@client}
      system_symbol={@system_symbol}
      fleet={@fleet}
      class="bg-base-200 w-72"
    >
        <.async_result :let={system} assign={@system}>
          <:loading><span class="loading loading-ring loading-lg"></span></:loading>
          <:failed :let={_failure}>There was an error loading the system.</:failed>

          <header>
            <h1 class="text-xl font-bold">{system["name"]}</h1>
            <p>System</p>
          </header>

        </.async_result>
    </.live_component>
    """
  end

  def mount(_params, %{"token" => token}, socket) do
    client = Client.new(token)
    {:ok, %{status: 200, body: agent_body}} = Agents.my_agent(client)
    PubSub.subscribe(@pubsub, "agent:#{agent_body["data"]["symbol"]}")
    callsign = agent_body["data"]["symbol"]

    socket =
      socket
      |> assign(%{
        app_section: :galaxy,
        token: token,
        client: client,
        agent: AsyncResult.ok(agent_body["data"])
      })
      |> assign_async(:agent_automaton, fn ->
        case AutomationServer.automaton(callsign) do
          {:ok, a} -> {:ok, %{agent_automaton: a}}
          {:error, _} -> {:ok, %{agent_automaton: nil}}
        end
      end)
      |> load_fleet()

    {:ok, socket}
  end

  defp load_fleet(socket, page \\ 1) do
    client = socket.assigns.client

    assign(socket, :fleet, [])
    |> start_async(:load_fleet, fn ->
      case Fleet.list_ships(client, page: page) do
        {:ok, %{status: 200, body: body}} ->
          %{
            meta: body["meta"],
            data: body["data"]
          }

        {:ok, resp} ->
          {:error, resp}

        err ->
          err
      end
    end)
  end

  def handle_async(:load_fleet, {:ok, result}, socket) do
    page = Map.fetch!(result.meta, "page")

    socket =
      if page == 1 do
        assign(socket, :fleet, result.data)
      else
        assign(socket, :fleet, socket.assigns.fleet ++ result.data)
      end

    socket =
      if Enum.count(socket.assigns.fleet) < Map.fetch!(result.meta, "total") do
        load_fleet(socket, page + 1)
      else
        socket
      end

    {:noreply, socket}
  end

  def handle_params(params, _uri, socket) do
    socket =
      socket
      |> assign(%{
        system_symbol: params["system_symbol"],
        waypoint_symbol: params["waypoint_symbol"]
      })
      |> then(fn socket ->
        client = socket.assigns.client
        system_symbol = socket.assigns.system_symbol

        assign_async(socket, :system, fn ->
          case Systems.get_system(client, system_symbol) do
            {:ok, %{body: body, status: 200}} ->
              {:ok, %{system: body["data"]}}
          end
        end)
      end)

    {:noreply, socket}
  end

  defp orbital_tree(system) do
    Enum.reduce(system["waypoints"], %{}, fn waypoint, tree ->
      access_path =
        orbital_path(system, waypoint["symbol"])
        |> Enum.map(fn wp_symbol ->
          Access.key(wp_symbol, %{})
        end)
        |> then(fn path ->
          path ++ [Access.key(waypoint["symbol"])]
        end)

      put_in(tree, access_path, waypoint)
    end)
  end

  defp orbital_path(system, waypoint_symbol, path \\ []) do
    waypoint = Enum.find(system["waypoints"], fn wp -> wp["symbol"] == waypoint_symbol end)

    if orbits = waypoint["orbits"] do
      orbital_path(system, orbits, [orbits | path])
    else
      path
    end
  end
end
