defmodule SpacetradersClientWeb.FleetComponent do
  use SpacetradersClientWeb, :live_component
  use Timex

  alias Phoenix.LiveView.AsyncResult
  alias SpacetradersClient.Game.Ship
  alias SpacetradersClient.Repo
  alias SpacetradersClient.Fleet

  attr :ship_symbol, :string, required: true

  def render(assigns) do
    ~H"""
    <div class="p-4">
      <div class="overflow-y-auto">
        <.live_component
          module={SpacetradersClientWeb.ShipComponent}
          id={"ship-#{@ship_symbol}"}
          ship_symbol={@ship_symbol}
        />
      </div>
    </div>
    """
  end

  def update(%{ship_symbol: ship_symbol}, socket) do
    ship =
      Repo.get(Ship, ship_symbol)
      |> Repo.preload([:nav_waypoint, :cargo_items])

    socket =
      socket
      |> assign(%{
        ship_symbol: ship_symbol,
        ship: AsyncResult.ok(ship)
      })

    {:ok, socket}
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
