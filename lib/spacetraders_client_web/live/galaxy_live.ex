defmodule SpacetradersClientWeb.GalaxyLive do
  use SpacetradersClientWeb, :live_view

  alias Phoenix.LiveView.AsyncResult
  alias Phoenix.PubSub
  alias SpacetradersClient.Agents
  alias SpacetradersClient.Systems
  alias SpacetradersClient.Client

  @pubsub SpacetradersClient.PubSub

  def render(assigns) do
    ~H"""
    Hi
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

    {:ok, socket}
  end

  def handle_params(params, _uri, socket) do
    socket =
      socket
      |> assign(%{
        system_symbol: params["system_symbol"],
        waypoint_symbol: params["waypoint_symbol"]
      })
      |> then(fn socket ->
        if socket.assigns.live_action in [:system, :waypoint] do
          client = socket.assigns.client
          system_symbol = socket.assigns.system_symbol

          assign_async(socket, :system, fn ->
            case Systems.get_system(client, system_symbol) do
              {:ok, result} ->
                {:ok, %{system: result.body["data"]}}
            end
          end)
        else
          assign(socket, :ship, nil)
        end
      end)

    {:noreply, socket}
  end
end
