defmodule SpacetradersClientWeb.AutomationLive do
  use SpacetradersClientWeb, :live_view

  alias Phoenix.LiveView.AsyncResult
  alias Phoenix.PubSub
  alias SpacetradersClient.Agents
  alias SpacetradersClient.Client
  alias SpacetradersClient.Fleet
  alias SpacetradersClient.AutomationServer
  alias SpacetradersClient.AutomationSupervisor
  alias SpacetradersClient.ShipAutomaton

  @pubsub SpacetradersClient.PubSub

  def render(assigns) do
    ~H"""
    <.async_result :let={automaton} assign={@agent_automaton}>
      <:loading><span class="loading loading-ring loading-lg"></span></:loading>
      <:failed :let={_failure}>There was an error fetching automation data.</:failed>
      <form phx-change="update-automation">
      <label class="">
        Automate ships
        <input name="enable-automation" type="checkbox" checked={is_struct(automaton)} class="toggle" />
      </label>
      </form>
    </.async_result>
    """
  end

  def mount(_params, %{"token" => token}, socket) do
    client = Client.new(token)
    {:ok, %{status: 200, body: agent_body}} = Agents.my_agent(client)
    PubSub.subscribe(@pubsub, "agent:#{agent_body["data"]["symbol"]}")

    socket =
      socket
      |> assign(%{
        token: token,
        client: client,
        agent: AsyncResult.ok(agent_body["data"])
      })
      |> assign_async(:agent_automaton, fn ->
        case AutomationServer.automaton(agent_body["data"]["symbol"]) do
          {:ok, automaton} ->
            {:ok, %{agent_automaton: automaton}}

          {:error, _reason} ->
            {:ok, %{agent_automaton: nil}}
        end
      end)

    {:ok, socket}
  end

  def handle_params(_params, _uri, socket) do
    {:noreply, socket}
  end

  def handle_event("update-automation", params, socket) do
    if Map.get(params, "enable-automation", false) == "on" do
      {:ok, _pid} =
        DynamicSupervisor.start_child(
          AutomationSupervisor,
          {AutomationServer, token: socket.assigns.token}
        )
    else
      :ok = AutomationServer.stop({:global, socket.assigns.agent.result["symbol"]})
    end

    {:noreply, socket}
  end

  def handle_info({:automaton_stopped, automaton}, socket) do
    {:noreply, assign(socket, :agent_automaton, AsyncResult.ok(nil))}
  end

  def handle_info({:automation_started, automaton}, socket) do
    {:noreply, assign(socket, :agent_automaton, AsyncResult.ok(automaton))}
  end

  def handle_info(_, socket) do
    {:noreply, socket}
  end
end
