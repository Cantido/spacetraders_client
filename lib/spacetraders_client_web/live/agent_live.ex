defmodule SpacetradersClientWeb.AgentLive do
  use SpacetradersClientWeb, :live_view

  alias Phoenix.LiveView.AsyncResult

  def render(assigns) do
    ~H"""
    <section class="p-8 h-full w-full overflow-y-auto">
      <header class="mb-4">
        <h2 class="text-neutral-500">Agent</h2>

        <.async_result :let={agent} assign={@agent}>
          <:loading><span class="loading loading-ring loading-lg"></span></:loading>
          <:failed :let={_failure}>There was an error loading your agent.</:failed>
          <h1 class="text-2xl"><%= agent["symbol"] %></h1>
        </.async_result>
      </header>
    </section>
    """
  end

  on_mount {SpacetradersClientWeb.GameLoader, :agent}

  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(%{
        app_section: :agent,
        agent_automaton: AsyncResult.loading()
      })

    {:ok, socket}
  end
end
