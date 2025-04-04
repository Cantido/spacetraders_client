defmodule SpacetradersClientWeb.AutomatonComponent do
  use SpacetradersClientWeb, :live_component

  alias SpacetradersClient.ShipAutomaton
  alias SpacetradersClient.Utility
  alias SpacetradersClient.Automation.ShipAutomationTick
  alias SpacetradersClient.Automation.ShipTask
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
        <div class="bg-base-200 text-base-content rounded-box p-4">
          <div class="flex flex-row gap-8">
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
              <.parameters_table task={@selected_task} />
            </div>

            <div class="basis-1/2">
              <p class="mb-4 font-bold text-lg">Decision factors</p>
              <.decision_factors_table task={@selected_task} />
            </div>
          </div>

          <section>
            <p class="mb-4 font-bold text-xl">Task History</p>
            <ul class="timeline timeline-compact timeline-vertical">
              <li :for={{task, index} <- Enum.with_index(@task_history)}>
                <hr :if={index != 0} />
                <div class="timeline-start text-xs text-base-content/50">
                  <time phx-hook="LocalDateTime" id={"task-#{task.task.id}-start-time"} datetime={DateTime.to_iso8601(ShipTask.start_time(task.task))}></time>
                </div>
                <div class="timeline-middle"><Heroicons.check_circle solid class="w-5 h-5" /></div>
                <div class="timeline-end w-full">
                  <div tabindex={index} class="collapse bg-base-300">
                    <div class="collapse-title text-lg">
                      {task.task.name}
                    </div>
                    <div class="collapse-content flex gap-8">
                      <div class="basis-1/3 pb-4">
                        <table class="table">
                          <tbody>
                            <tr>
                              <th>utility</th>
                              <td class="font-mono">{:erlang.float_to_binary(task.task.utility, decimals: 3)}</td>
                            </tr>
                            <tr>
                              <th>outcome</th>
                              <td>success</td>
                            </tr>
                          </tbody>
                        </table>
                      </div>

                      <div class="basis-1/3 pb-4">
                        <p class="mb-4 font-bold text-lg">Parameters</p>
                        <.parameters_table task={task.task} />
                      </div>

                      <div class="basis-1/3 pb-4">
                        <p class="mb-4 font-bold text-lg">Decision factors</p>
                        <.decision_factors_table task={task.task} />
                      </div>
                    </div>
                  </div>
                </div>
                <hr :if={index < Enum.count(@task_history) - 1} />
              </li>
            </ul>
          </section>
        </div>
      </div>
    </div>
    """
  end

  attr :task, ShipTask, required: true

  defp parameters_table(assigns) do
    ~H"""
    <table class="table table-sm">
      <thead>
        <tr>
          <th class="w-1/2">Parameter</th>
          <th class="w-1/2">Value</th>
        </tr>
      </thead>
      <tbody>
        <%= for arg <- @task.float_args do %>
          <tr>
            <td class="font-mono">{arg.name}</td>
            <td class="font-mono">{:erlang.float_to_binary(arg.value, decimals: 3)}</td>
          </tr>
        <% end %>
        <%= for arg <- @task.string_args do %>
          <tr>
            <td class="font-mono">{arg.name}</td>
            <td class="font-mono">{inspect(arg.value)}</td>
          </tr>
        <% end %>
      </tbody>
    </table>
    """
  end

  attr :task, ShipTask, required: true

  defp decision_factors_table(assigns) do
    ~H"""
    <table class="table table-sm">
      <thead>
        <tr>
          <th class="w-1/3">Factor</th>
          <th class="w-1/6 text-right">Input</th>
          <th class="w-1/6 text-right">Output</th>
          <th class="w-1/6 text-right">Weight</th>
        </tr>
      </thead>
      <tbody>
        <%= for factor <- @task.decision_factors do %>
          <tr>
            <td class="font-mono">{factor.name}</td>
            <td class="font-mono text-right tabular-nums">
              {:erlang.float_to_binary(factor.input_value, decimals: 3)}
            </td>
            <td class="font-mono text-right tabular-nums">
              {:erlang.float_to_binary(factor.output_value, decimals: 3)}
            </td>
            <td class="font-mono text-right tabular-nums">
              {:erlang.float_to_binary(factor.weight, decimals: 3)}
            </td>
          </tr>
        <% end %>
      </tbody>
    </table>
    """
  end

  def mount(socket) do
    {:ok, assign(socket, :selected_action, nil)}
  end

  def update(assigns, socket) do
    socket = assign(socket, assigns)

    socket = assign(socket, :selected_task, assigns.ship_automation_tick.active_task)

    tick_index_query =
      from at in ShipAutomationTick,
        select: %{
          tick_id: at.id,
          index: rank() |> over(order_by: at.timestamp)
        }

    task_start_times_query =
      from t in ShipTask,
        join: at in assoc(t, :active_automation_ticks),
        join: tindex in subquery(tick_index_query),
        on: at.id == tindex.tick_id,
        where: at.ship_id == ^socket.assigns.ship_automation_tick.ship_id,
        group_by: t.id,
        select: %{
          task_id: t.id,
          start_timestamp: min(at.timestamp),
          start_tick_index: min(tindex.index)
        }

    task_history =
      Repo.all(
        from t in ShipTask,
          join: tstart in subquery(task_start_times_query),
          on: t.id == tstart.task_id,
          order_by: [desc: tstart.task_id],
          select: %{
            task: t,
            started_tick_index: tstart.start_tick_index
          },
          preload: [:active_automation_ticks, :float_args, :string_args, :decision_factors],
          limit: 10,
          offset: 1
      )

    socket =
      socket
      |> assign(%{
        task_history: task_history
      })

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
          task_finished?: is_nil(automaton.current_action),
          task_history: task_history
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
