defmodule SpacetradersClientWeb.GameLoader do
  alias Phoenix.Component
  alias Phoenix.LiveView
  alias Phoenix.LiveView.AsyncResult
  alias SpacetradersClient.Client
  alias SpacetradersClient.Agents
  alias SpacetradersClient.Fleet

  import Phoenix.LiveView

  def on_mount(:agent, _params, %{"token" => token}, socket) do
    client = Client.new(token)

    {:ok, %{status: 200, body: agent_body}} = Agents.my_agent(client)

    socket =
      socket
      |> Component.assign(%{
        token: token,
        client: client,
        agent: AsyncResult.ok(agent_body["data"])
      })

    {:cont, socket}
  end

  def load_fleet(socket, page \\ 1) do
    client = socket.assigns.client

    socket
    |> Component.assign(:fleet, AsyncResult.loading())
    |> LiveView.start_async(:load_fleet, fn ->
      case Fleet.list_ships(client, page: page) do
        {:ok, %{status: 200, body: body}} ->
          %{
            meta: body["meta"],
            data: body["data"]
          }

        {:ok, resp} ->
          {:error, resp}

        err ->
          err
      end
    end)
    |> LiveView.attach_hook(:load_fleet, :handle_async, &handle_async/3)
  end

  defp handle_async(:load_fleet, {:ok, result}, socket) do
    page = Map.fetch!(result.meta, "page")

    socket =
      if page == 1 do
        Component.assign(socket, :fleet, AsyncResult.loading(result.data))
      else
        Component.assign(
          socket,
          :fleet,
          AsyncResult.loading(socket.assigns.fleet, socket.assigns.fleet.loading ++ result.data)
        )
      end

    socket =
      if Enum.count(socket.assigns.fleet.loading) < Map.fetch!(result.meta, "total") do
        load_fleet(socket, page + 1)
      else
        Component.assign(
          socket,
          :fleet,
          AsyncResult.ok(socket.assigns.fleet, socket.assigns.fleet.loading)
        )
      end

    {:halt, socket}
  end

  defp handle_async(_event, _params, socket) do
    {:cont, socket}
  end
end
