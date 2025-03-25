defmodule SpacetradersClientWeb.GalaxyLive do
  use SpacetradersClientWeb, :live_view

  alias Phoenix.LiveView.AsyncResult
  alias Phoenix.PubSub
  alias SpacetradersClient.AutomationServer
  alias SpacetradersClient.Agents
  alias SpacetradersClient.Systems
  alias SpacetradersClient.Client

  @pubsub SpacetradersClient.PubSub

  def render(assigns) do
    ~H"""
    hi
    """
  end

  def mount(_params, %{"token" => token}, socket) do
    client = Client.new(token)
    {:ok, %{status: 200, body: agent_body}} = Agents.my_agent(client)
    PubSub.subscribe(@pubsub, "agent:#{agent_body["data"]["symbol"]}")
    callsign = agent_body["data"]["symbol"]

    socket =
      socket
      |> assign(%{
        app_section: :galaxy,
        token: token,
        client: client,
        agent: AsyncResult.ok(agent_body["data"])
      })
      |> assign_async(:agent_automaton, fn ->
        case AutomationServer.automaton(callsign) do
          {:ok, a} -> {:ok, %{agent_automaton: a}}
          {:error, _} -> {:ok, %{agent_automaton: nil}}
        end
      end)

    {:ok, socket}
  end
end
