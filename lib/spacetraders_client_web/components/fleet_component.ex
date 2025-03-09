defmodule SpacetradersClientWeb.FleetComponent do
  use SpacetradersClientWeb, :live_component
  use Timex

  alias SpacetradersClient.ShipAutomaton

  attr :fleet, :list, required: true
  attr :fleet_automata, :map, default: %{}

  def render(assigns) do
    ~H"""
    <div class="h-screen overflow-y-auto">
      <table class="table table-xs table-zebra">
        <thead>
          <tr>
            <th class="w-48">Symbol</th>
            <th class="w-32">Role</th>
            <th class="w-32">System</th>
            <th class="w-32">Waypoint</th>
            <th class="w-64">Current task</th>
            <th class="w-32">Task runtime</th>
          </tr>
        </thead>
        <tbody>
          <%= for ship <- @fleet do %>
            <%
              ship_automaton =
                if @fleet_automata do
                  Map.get(@fleet_automata, ship["symbol"])
                end
            %>
            <tr>
              <td><%= ship["symbol"] %></td>
              <td><%= ship["registration"]["role"] %></td>
              <td><%= ship["nav"]["systemSymbol"] %></td>
              <td><%= ship["nav"]["waypointSymbol"] %></td>
              <td>
                <%= if ship_automaton do %>
                  <%= current_automation_task(ship_automaton) %>
                <% end %>
              </td>
              <td>
                <%= if @fleet_automata do %>
                  <.action_runtime automaton={ship_automaton} />
                <% end %>
              </td>
            </tr>
          <% end %>
        </tbody>
      </table>
    </div>
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
end
