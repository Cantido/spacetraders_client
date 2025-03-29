defmodule SpacetradersClientWeb.AutomationLive do
  use SpacetradersClientWeb, :live_view

  alias Phoenix.LiveView.AsyncResult
  alias SpacetradersClient.AutomationServer
  alias SpacetradersClient.AutomationSupervisor
  alias SpacetradersClient.AgentAutomaton

  def render(assigns) do
    ~H"""
    <.async_result :let={automaton} assign={@agent_automaton}>
      <:loading>
      <button name="enable-automation" class="btn btn-neutral" phx-click="start-automation" disabled="true">
        <span class="loading loading-ring loading-lg"></span>
        Loading automation...
      </button>
      </:loading>
      <:failed :let={_failure}>
        There was an error fetching automation data.
      </:failed>
      <%= if is_struct(automaton, AgentAutomaton) do %>
        <button class="btn btn-error" phx-click="stop-automation">
          Stop game automation
        </button>
      <% else %>
        <button class="btn btn-primary" phx-click="start-automation">
          Start game automation
        </button>
      <% end %>

    </.async_result>
    """
  end

  on_mount {SpacetradersClientWeb.GameLoader, :agent}

  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(%{
        app_section: :automation
      })

    {:ok, socket}
  end

  def handle_params(_params, _uri, socket) do
    {:noreply, socket}
  end

  def handle_event("start-automation", _params, socket) do
    {:ok, _pid} =
      DynamicSupervisor.start_child(
        AutomationSupervisor,
        {AutomationServer, token: socket.assigns.token}
      )

    {:noreply, socket}
  end

  def handle_event("stop-automation", _params, socket) do
    :ok = AutomationServer.stop(socket.assigns.agent.result.symbol)

    {:noreply, assign(socket, :agent_automaton, AsyncResult.ok(nil))}
  end
end
