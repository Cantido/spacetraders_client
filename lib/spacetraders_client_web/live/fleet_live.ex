defmodule SpacetradersClientWeb.FleetLive do
  use SpacetradersClientWeb, :live_view

  alias Phoenix.LiveView.AsyncResult
  alias SpacetradersClient.ShipAutomaton
  alias SpacetradersClient.Automation.ShipAutomationTick
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
            <td><.link navigate={~p"/game/fleet/#{ship.symbol}"} class="hover:link"><%= ship.symbol %></.link></td>
            <td><%= ship.registration_role %></td>
            <td>
              <.link navigate={~p"/game/systems/#{ship.nav_waypoint.system_symbol}"} class="hover:link">
                <%= ship.nav_waypoint.system_symbol %>
              </.link>
            </td>
            <td>
              <.link navigate={~p"/game/systems/#{ship.nav_waypoint.system_symbol}/waypoints/#{ship.nav_waypoint.symbol}"} class="hover:link">
                <%= ship.nav_waypoint.symbol %>
              </.link>
            </td>


            <% automation_tick = @automation_ticks[ship.symbol] %>

            <td>
              <%= if automation_tick do %>
                <%= automation_tick.active_task.name %>
              <% end %>
            </td>
            <td>
              <%= if automation_tick do %>
                <.action_runtime automation_tick={automation_tick} />
              <% end %>
            </td>
          </tr>
        </tbody>
      </table>
    </.async_result>
    """
  end

  on_mount {SpacetradersClientWeb.GameLoader, :agent}

  def mount(_params, _session, socket) do
    agent_symbol = socket.assigns.agent.result.symbol

    fleet =
      Repo.all(
        from s in Ship,
          where: [agent_symbol: ^socket.assigns.agent.result.symbol],
          preload: [:nav_waypoint]
      )

    fleet_automation_ticks =
      Repo.all(
        from sat in ShipAutomationTick,
          join: s in assoc(sat, :ship),
          where: s.agent_symbol == ^agent_symbol
      )
      |> Repo.preload(active_task: :active_automation_ticks)
      |> Map.new(fn tick ->
        {tick.ship_symbol, tick}
      end)

    socket =
      socket
      |> assign(%{
        app_section: :fleet,
        fleet: AsyncResult.ok(fleet),
        automation_ticks: fleet_automation_ticks
      })

    {:ok, socket}
  end

  attr :automation_tick, ShipAutomationTick, required: true

  defp action_runtime(assigns) do
    ~H"""
    <.stopwatch id={@automation_tick.ship_symbol <> "-task-duration"} start={List.first(@automation_tick.active_task.active_automation_ticks).timestamp} />
    """
  end

  attr :id, :string, required: true
  attr :start, DateTime, required: true

  defp stopwatch(assigns) do
    ~H"""
    <span id={@id} phx-hook="Stopwatch" data-since={DateTime.to_iso8601(@start)}></span>
    """
  end
end
