defmodule SpacetradersClientWeb.LoadingLive do
  use SpacetradersClientWeb, :live_view

  alias Phoenix.LiveView.AsyncResult
  alias SpacetradersClient.Client

  def render(assigns) do
    ~H"""
    <div>
      <div>
      loading your stuff!
      </div>

      <div>
        Agent

        <progress :if={!@agent.ok?} class="progress w-56" ></progress>
        <progress :if={@agent.ok?} class="progress progress-success w-56" value="1" max="1"></progress>

      </div>
      <div>
        Fleet

        <progress :if={!@fleet.ok? && is_nil(@fleet.loading[:total])} class="progress w-56" ></progress>
        <progress :if={!@fleet.ok? && is_integer(@fleet.loading[:total])} class="progress w-56" value={@fleet.loading.progress} max={@fleet.loading.total} ></progress>
        <progress :if={@fleet.ok?} class="progress progress-success w-56" value="1" max="1"></progress>
      </div>
    </div>
    """
  end

  def mount(_params, %{"token" => token}, socket) do
    client = Client.new(token)

    SpacetradersClientWeb.GameLoader.load_user_async(client, self())

    socket =
      socket
      |> assign(%{
        token: token,
        client: client,
        agent: AsyncResult.loading(),
        fleet: AsyncResult.loading([])
      })

    {:ok, socket, layout: false}
  end

  def handle_info({:load_progress, :agent, _, _, agent}, socket) do
    {:noreply, assign(socket, :agent, AsyncResult.ok(agent))}
  end

  def handle_info({:load_progress, :fleet, current, total, fleet}, socket) do
    if current == total do
      {:noreply, assign(socket, :fleet, AsyncResult.ok(fleet))}
    else
      {:noreply, assign(socket, :fleet, AsyncResult.loading(%{total: total, progress: current}))}
    end
  end

  def handle_info(_, socket) do
    {:noreply, socket}
  end
end
