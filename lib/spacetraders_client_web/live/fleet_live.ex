defmodule SpacetradersClientWeb.FleetLive do
  use SpacetradersClientWeb, :live_view
  use Timex

  alias Phoenix.LiveView.AsyncResult
  alias Phoenix.PubSub
  alias SpacetradersClient.Agents
  alias SpacetradersClient.AutomationServer
  alias SpacetradersClient.Client
  alias SpacetradersClient.Fleet
  alias SpacetradersClient.Systems
  alias SpacetradersClient.ShipAutomaton

  @pubsub SpacetradersClient.PubSub

  attr :fleet, :list, required: true
  attr :ship_symbol, :string, default: nil

  def render(assigns) do
    ~H"""
    <div class="">
      <div :if={@live_action == :show}>

        <.async_result :let={ship} assign={@ship}>
          <:loading><span class="loading loading-ring loading-lg"></span></:loading>
          <:failed :let={_failure}>There was an error loading the ship.</:failed>

          <.async_result :let={agent_automaton} assign={@agent_automaton}>
            <:loading><span class="loading loading-ring loading-lg"></span></:loading>
            <:failed :let={_failure}>There was an error loading the agent.</:failed>


            <div class="overflow-y-auto">
              <.live_component
                module={SpacetradersClientWeb.ShipComponent}
                id={"ship-#{@ship_symbol}"}
                client={@client}
                ship={ship}
                automaton={get_in(agent_automaton, [Access.key(:ship_automata), @ship_symbol])}
              />
            </div>
          </.async_result>
        </.async_result>
      </div>

      <.async_result :let={agent_automaton} assign={@agent_automaton}>
        <:loading><span class="loading loading-ring loading-lg"></span></:loading>
        <:failed :let={_failure}>There was an error loading the agent.</:failed>
        <.fleet_table :if={@live_action == :index} fleet={@fleet} fleet_automata={if agent_automaton, do: agent_automaton.ship_automata, else: %{}} />
      </.async_result>
    </div>
    """
  end

  attr :fleet, :list, required: true
  attr :fleet_automata, :map, default: %{}

  defp fleet_table(assigns) do
    ~H"""
    <table class="table table-xs table-zebra">
      <thead>
        <tr>
          <th class="w-48">Ship</th>
          <th class="w-32">Role</th>
          <th class="w-32">System</th>
          <th class="w-32">Waypoint</th>
          <th class="w-64">Current task</th>
          <th class="w-32">Task runtime</th>
        </tr>
      </thead>
      <tbody>
        <tr
          :for={ship <- @fleet}
        >
          <td><.link patch={~p"/game/fleet/#{ship["symbol"]}"} class="hover:link"><%= ship["symbol"] %></.link></td>
          <td><%= ship["registration"]["role"] %></td>
          <td>
            <.link patch={~p"/game/systems/#{ship["nav"]["systemSymbol"]}"} class="hover:link">
              <%= ship["nav"]["systemSymbol"] %>
            </.link>
          </td>
          <td>
            <.link patch={~p"/game/systems/#{ship["nav"]["systemSymbol"]}/waypoints/#{ship["nav"]["waypointSymbol"]}"} class="hover:link">
              <%= ship["nav"]["waypointSymbol"] %>
            </.link>
          </td>
          <% ship_automaton = @fleet_automata[ship["symbol"]] %>
          <td>
            <%= if ship_automaton do %>
              <%= current_automation_task(ship_automaton) %>
            <% end %>
          </td>
          <td>
            <%= if ship_automaton do %>
              <.action_runtime automaton={ship_automaton} />
            <% end %>
          </td>
        </tr>
      </tbody>
    </table>
    """
  end

  attr :automaton, ShipAutomaton, required: true

  defp action_runtime(assigns) do
    ~H"""
    <%= if @automaton.current_action_started_at do %>
      <.stopwatch id={@automaton.ship_symbol <> "-task-duration"} start={@automaton.current_action_started_at} />
    <% end %>
    """
  end

  attr :id, :string, required: true
  attr :start, DateTime, required: true

  defp stopwatch(assigns) do
    ~H"""
    <span id={@id} phx-hook="Stopwatch" data-since={DateTime.to_iso8601(@start)}></span>
    """
  end

  defp format_time_part(n) do
    Integer.to_string(n) |> String.pad_leading(2, "0")
  end

  defp current_automation_task(nil), do: nil

  defp current_automation_task(automaton) do
    if task = automaton.current_action do
      task.name
    end
  end

  def mount(_params, %{"token" => token}, socket) do
    client = Client.new(token)
    {:ok, %{status: 200, body: agent_body}} = Agents.my_agent(client)
    PubSub.subscribe(@pubsub, "agent:#{agent_body["data"]["symbol"]}")

    callsign = agent_body["data"]["symbol"]

    socket =
      socket
      |> assign(%{
        client: client,
        agent: AsyncResult.ok(agent_body["data"])
      })
      |> assign_async(:agent_automaton, fn ->
        case AutomationServer.automaton(callsign) do
          {:ok, a} -> {:ok, %{agent_automaton: a}}
          {:error, _} -> {:ok, %{agent_automaton: nil}}
        end
      end)
      |> assign(:fleet, [])
      |> load_fleet()

    {:ok, socket}
  end

  def handle_params(params, _uri, socket) do
    socket =
      socket
      |> assign(%{
        ship_symbol: params["ship_symbol"]
      })
      |> then(fn socket ->
        if socket.assigns.live_action == :show do
          client = socket.assigns.client
          ship_symbol = socket.assigns.ship_symbol

          assign_async(socket, [:ship, :system], fn ->
            with {:ok, ship_result} <- Fleet.get_ship(client, ship_symbol),
                 {:ok, system_result} <-
                   Systems.get_system(client, ship_result.body["data"]["nav"]["systemSymbol"]) do
              {:ok, %{ship: ship_result.body["data"], system: system_result.body["data"]}}
            end
          end)
        else
          socket
          |> assign(:ship, nil)
          |> assign(:system, nil)
        end
      end)

    {:noreply, socket}
  end

  defp load_fleet(socket, page \\ 1) do
    client = socket.assigns.client

    start_async(socket, :load_fleet, fn ->
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

  def handle_event("dock-ship", %{"ship-symbol" => ship_symbol}, socket) do
    {:ok, %{status: 200, body: body}} = Fleet.dock_ship(socket.assigns.client, ship_symbol)

    socket =
      update_ship(socket, ship_symbol, fn ship ->
        Map.put(ship, "nav", body["data"]["nav"])
      end)
      |> put_flash(:info, "Ship #{ship_symbol} docked successfully")

    {:noreply, socket}
  end

  def handle_event(
        "navigate-ship",
        %{"ship-symbol" => ship_symbol, "waypoint-symbol" => waypoint_symbol} = params,
        socket
      ) do
    flight_mode = Map.get(params, "flight-mode", "CRUISE")

    socket =
      case Fleet.set_flight_mode(socket.assigns.client, ship_symbol, flight_mode) do
        {:ok, %{status: 200, body: body}} ->
          socket =
            update_ship(socket, ship_symbol, fn ship ->
              Map.put(ship, "nav", body["data"]["nav"])
            end)

          socket
      end

    case Fleet.navigate_ship(socket.assigns.client, ship_symbol, waypoint_symbol) do
      {:ok, %{status: 200, body: body}} ->
        socket =
          update_ship(socket, ship_symbol, fn ship ->
            Map.put(ship, "nav", body["data"]["nav"])
          end)

        {:noreply, socket}

      {:ok, %{status: 400, body: %{"error" => %{"code" => 4203, "data" => data}}}} ->
        socket =
          put_flash(
            socket,
            :error,
            "Not enough fuel, #{data["fuelRequired"]} fuel is required, but only #{data["fuelAvailable"]} is available"
          )

        {:noreply, socket}
    end
  end

  def handle_event("orbit-ship", %{"ship-symbol" => ship_symbol}, socket) do
    {:ok, %{status: 200, body: body}} = Fleet.orbit_ship(socket.assigns.client, ship_symbol)

    socket =
      update_ship(socket, ship_symbol, fn ship ->
        Map.put(ship, "nav", body["data"]["nav"])
      end)
      |> put_flash(:info, "Ship #{ship_symbol} undocked successfully")

    {:noreply, socket}
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

  def handle_info({:automaton_starting, _callsign}, socket) do
    {:noreply, assign(socket, :agent_automaton, AsyncResult.loading())}
  end

  def handle_info({:automaton_started, automaton}, socket) do
    {:noreply, assign(socket, :agent_automaton, AsyncResult.ok(automaton))}
  end

  def handle_info({:automaton_updated, automaton}, socket) do
    {:noreply, assign(socket, :agent_automaton, AsyncResult.ok(automaton))}
  end

  def handle_info({:automaton_stopped, _automaton}, socket) do
    {:noreply, assign(socket, :agent_automaton, AsyncResult.ok(nil))}
  end

  def handle_info(_, socket) do
    {:noreply, socket}
  end

  defp update_ship(%Phoenix.LiveView.Socket{} = socket, ship_symbol, ship_update_fn) do
    i =
      Enum.find_index(socket.assigns.fleet.result, fn ship ->
        ship["symbol"] == ship_symbol
      end)

    fleet =
      if is_integer(i) do
        List.update_at(socket.assigns.fleet.result, i, ship_update_fn)
      else
        socket.assigns.fleet.result
      end

    assign(socket, :fleet, AsyncResult.ok(fleet))
  end
end
