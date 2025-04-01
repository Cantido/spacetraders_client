defmodule SpacetradersClientWeb.AutomatonComponent do
  use SpacetradersClientWeb, :live_component

  alias SpacetradersClient.ShipAutomaton
  alias SpacetradersClient.Utility
  alias SpacetradersClient.Automation.ShipAutomationTick
  alias SpacetradersClient.Repo

  import Ecto.Query, except: [update: 3]

  attr :ship_automation_tick, ShipAutomationTick, required: true

  def render(assigns) do
    ~H"""
    <div>
      <div class="rounded-xl p-6 bg-neutral text-neutral-content mb-8">
        <h2 class="mb-4 flex flex-row gap-4 items-center">
          <Heroicons.cog class="w-12 h-12" />
          <div>
            <div class="font-bold text-xl">
              Automation task in progress
            </div>
          </div>
        </h2>
        <div class="flex flex-row gap-8 bg-base-200 rounded-box p-4">
          <div>
            <p class="mb-4 font-bold text-lg">Tasks evaluated</p>
            <ul class="menu w-56">
              <%= for action <- [@ship_automation_tick.active_task | @ship_automation_tick.alternative_tasks] do %>
                <li class="mb-1">
                  <a
                    class={if @selected_task.id == action.id, do: ["menu-active"], else: []}
                    phx-click="select-action"
                    phx-value-action-id={action.id}
                    phx-target={@myself}
                  >
                    <%= if action.id == @ship_automation_tick.active_task.id do %>
                      <span class="tooltip" data-tip="The ship chose to perform this action">
                        <Heroicons.chevron_right class="w-4 h-4" />
                      </span>
                    <% end %>
                    <span class="me-2">{action.name}</span>
                    <span>{:erlang.float_to_binary(action.utility, decimals: 3)}</span>
                  </a>
                </li>
              <% end %>
            </ul>
          </div>

          <div class="basis-1/2">
            <p class="mb-4 font-bold text-lg">Parameters</p>
            <table class="table table-sm">
              <thead>
                <tr>
                  <th class="w-1/2">Parameter</th>
                  <th class="w-1/2">Value</th>
                </tr>
              </thead>
              <tbody>
                <%= for arg <- @selected_task.float_args do %>
                  <tr>
                    <td class="font-mono">{arg.name}</td>
                    <td class="font-mono">{:erlang.float_to_binary(arg.value, decimals: 3)}</td>
                  </tr>
                <% end %>
                <%= for arg <- @selected_task.string_args do %>
                  <tr>
                    <td class="font-mono">{arg.name}</td>
                    <td class="font-mono">{inspect(arg.value)}</td>
                  </tr>
                <% end %>
              </tbody>
            </table>
          </div>

          <div class="basis-1/2">
            <p class="mb-4 font-bold text-lg">Decision factors</p>
            <table class="table table-sm">
              <thead>
                <tr>
                  <th class="w-1/3">Factor</th>
                  <th class="w-1/6">Input</th>
                  <th class="w-1/6">Output</th>
                  <th class="w-1/6">Weight</th>
                </tr>
              </thead>
              <tbody>
                <%= for factor <- @selected_task.decision_factors do %>
                  <tr>
                    <td class="font-mono">{factor.name}</td>
                    <td class="font-mono text-right tabular-nums">{:erlang.float_to_binary(factor.input_value, decimals: 3)}</td>
                    <td class="font-mono text-right tabular-nums">{:erlang.float_to_binary(factor.output_value, decimals: 3)}</td>
                    <td class="font-mono text-right tabular-nums">{:erlang.float_to_binary(factor.weight, decimals: 3)}</td>
                  </tr>
                <% end %>
              </tbody>
            </table>
          </div>
        </div>
      </div>
    </div>
    """
  end

  def mount(socket) do
    {:ok, assign(socket, :selected_action, nil)}
  end

  def update(assigns, socket) do
    socket = assign(socket, assigns)

    socket = assign(socket, :selected_task, assigns.ship_automation_tick.active_task)

    socket =
      if assigns[:automaton] do
        automaton = socket.assigns.automaton

        latest_action =
          if automaton.current_action do
            automaton.current_action
          else
            List.first(automaton.action_history)
          end

        selected_action =
          if is_nil(socket.assigns.selected_action) do
            latest_action
          else
            id = socket.assigns.selected_action.id

            if action = Enum.find(automaton.alternative_actions, fn a -> a.id == id end) do
              action
            else
              latest_action
            end
          end

        assign(socket, %{
          selected_action: selected_action,
          latest_action: latest_action,
          task_finished?: is_nil(automaton.current_action)
        })
      else
        socket
      end

    {:ok, socket}
  end

  def handle_event("select-action", %{"action-id" => action_id}, socket) do
    ship_automation_tick = socket.assigns.ship_automation_tick

    selected_task =
      Enum.find(ship_automation_tick.alternative_tasks, fn task ->
        task.id == action_id
      end)

    socket = assign(socket, :selected_task, selected_task)

    {:noreply, socket}
  end
end
