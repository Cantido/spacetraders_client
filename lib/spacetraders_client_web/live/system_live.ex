defmodule SpacetradersClientWeb.SystemLive do
  use SpacetradersClientWeb, :live_view

  alias SpacetradersClient.Game.System
  alias SpacetradersClient.Repo

  def render(assigns) do
    ~H"""
    <.live_component
      module={SpacetradersClientWeb.OrbitalsMenuComponent}
      id="orbitals"
      agent_symbol={@agent_symbol}
      system_symbol={@system_symbol}
      class="bg-base-200 w-72"
    >
      <div class="p-4">
        <header>
          <h1 class="text-xl font-bold">{@system.name}</h1>
          <p>{@system.type} system</p>
        </header>
      </div>

    </.live_component>
    """
  end

  on_mount {SpacetradersClientWeb.GameLoader, :agent}

  def mount(%{"system_symbol" => system_symbol}, _session, socket) do
    system = Repo.get(System, system_symbol)

    socket =
      socket
      |> assign(%{
        app_section: :galaxy,
        system_symbol: system_symbol,
        system: system
      })

    {:ok, socket}
  end
end
