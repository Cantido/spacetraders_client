defmodule SpacetradersClientWeb.FleetLive do
  use SpacetradersClientWeb, :live_view

  alias Phoenix.LiveView.AsyncResult
  alias SpacetradersClient.ShipAutomaton
  alias SpacetradersClient.Game.Ship
  alias SpacetradersClient.Repo

  import Ecto.Query, except: [update: 3]

  attr :agent_symbol, :string, required: true
  attr :fleet_automata, :map, default: %{}

  def render(assigns) do
    ~H"""
    <.async_result :let={fleet} assign={@fleet}>
      <:loading><span class="loading loading-ring loading-lg"></span></:loading>
      <:failed :let={_failure}>There was an error loading your fleet.</:failed>
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
            :for={ship <- fleet}
          >
            <td><.link patch={~p"/game/fleet/#{ship.symbol}"} class="hover:link"><%= ship.symbol %></.link></td>
            <td><%= ship.registration_role %></td>
            <td>
              <.link patch={~p"/game/systems/#{ship.nav_waypoint.system_symbol}"} class="hover:link">
                <%= ship.nav_waypoint.system_symbol %>
              </.link>
            </td>
            <td>
              <.link patch={~p"/game/systems/#{ship.nav_waypoint.system_symbol}/waypoints/#{ship.nav_waypoint.symbol}"} class="hover:link">
                <%= ship.nav_waypoint_symbol %>
              </.link>
            </td>

            <.async_result :let={agent_automaton} assign={@agent_automaton}>
              <:loading>
                <td></td>
                <td></td>
              </:loading>
              <:failed :let={_failure}>
                <td></td>
                <td></td>
              </:failed>

              <% ship_automaton = get_in(agent_automaton, [Access.key(:ship_automata), ship.symbol]) %>

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
            </.async_result>
          </tr>
        </tbody>
      </table>
    </.async_result>
    """
  end

  on_mount {SpacetradersClientWeb.GameLoader, :agent}

  def mount(_params, _session, socket) do
    fleet =
      Repo.all(
        from s in Ship,
          where: [agent_symbol: ^socket.assigns.agent.result.symbol],
          preload: [:nav_waypoint]
      )

    socket =
      socket
      |> assign(%{
        app_section: :fleet,
        fleet: AsyncResult.ok(fleet)
      })

    {:ok, socket}
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

  defp current_automation_task(nil), do: nil

  defp current_automation_task(automaton) do
    if task = automaton.current_action do
      task.name
    end
  end
end
