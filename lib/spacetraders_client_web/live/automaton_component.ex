defmodule SpacetradersClientWeb.AutomatonComponent do
  alias SpacetradersClient.ShipAutomaton
  alias SpacetradersClient.Utility
  use SpacetradersClientWeb, :live_component

  attr :automaton, ShipAutomaton, required: true

  def render(assigns) do
    ~H"""
    <div>

        <div class="rounded-xl p-6 bg-neutral text-neutral-content mb-8">
          <h2 class="mb-4 flex flex-row gap-4 items-center">
            <.icon name="hero-cog" class="w-12 h-12" />
            <div>
              <div class="font-bold text-xl">
                <%= if @task_finished? do %>
                  Automation task completed
                <% else %>
                  Automation task in progress
                <% end %>
              </div>
            </div>
          </h2>
          <div class="flex flex-row gap-8 bg-base-200 rounded-box p-8">
            <div>
              <p class="mb-4 font-bold text-lg">Tasks evaluated</p>
              <ul class="menu w-56">
                <%= for action <- Enum.reject(@automaton.alternative_actions, &is_nil/1) do %>
                  <li class="mb-1">
                    <a
                      class={[@selected_action && action.id == @selected_action.id && "active"]}
                      phx-click="select-action"
                      phx-value-action-id={action.id}
                      phx-target={@myself}
                    >
                      <%= if @latest_action && action.id == @latest_action.id do %>
                        <span class="tooltip" data-tip="The ship chose to perform this action"><.icon name="hero-chevron-right" class="w-4 h-4" /></span>
                      <% else %>
                        <span></span>
                      <% end %>
                      <span><%= action.name %></span>
                      <span><.number value={Float.round(Utility.score(action.utility), 3)} /></span>
                    </a>
                  </li>
                <% end %>
              </ul>

            </div>
            <div class="divider divider-horizontal"></div>

            <%= if @selected_action do %>

              <div class="grow flex flex-row justify-between">
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
                      <%= for {key, val} <- @selected_action.args do %>
                        <tr>
                          <td class="font-mono"><%= key %></td>
                          <td class="font-mono"><%= inspect val %></td>
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
                      <%= for factor <- @selected_action.utility.factors do %>
                        <tr>
                          <td class="font-mono"><%= factor.name %></td>
                          <td class="font-mono"><.number value={factor.input} /></td>
                          <td class="font-mono"><.number value={factor.output} /></td>
                          <td class="font-mono"><.number value={Map.get(factor, :weight, 1)} /></td>
                        </tr>
                      <% end %>
                    </tbody>

                  </table>
                </div>
              </div>
            <% end %>
          </div>
        </div>
    </div>
    """
  end

  defp number(assigns) do
    ~H"""
    <%= format_number(@value) %>
    """
  end

  def format_number(n) do
    if is_float(n) do
      Float.round(n, 3)
      |> to_string()
      |> String.pad_trailing(5, "0")
    else
      to_string(n)
    end
  end

  def mount(socket) do
    {:ok, assign(socket, :selected_action, nil)}
  end

  def update(assigns, socket) do
    socket = assign(socket, assigns)

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
    automaton = socket.assigns.automaton

    selected_action =
      Enum.find(automaton.alternative_actions, fn action ->
        action.id == action_id
      end)

    if selected_action do
      {:noreply, assign(socket, :selected_action, selected_action)}
    else
      {:noreply, socket}
    end
  end
end
