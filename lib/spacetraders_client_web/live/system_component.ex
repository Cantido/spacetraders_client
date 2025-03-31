defmodule SpacetradersClientWeb.SystemComponent do
  use SpacetradersClientWeb, :live_component

  alias SpacetradersClient.Game.System
  alias SpacetradersClient.Game.Ship
  alias SpacetradersClient.Repo

  import Ecto.Query, except: [update: 3]

  def render(assigns) do
    ~H"""
    <div class="p-4">
      <header class="mb-8">
        <h1 class="text-2xl font-bold">
          <span>{@system.name}</span>
          <span class="text-lg font-normal text-base-content/50">({@system.symbol})</span>
        </h1>
        <p>
          {@system.type} system in the {@system.constellation} constellation
        </p>
      </header>

      <div>
        <div class="stats">
          <div class="stat">
            <div class="stat-title">Waypoints</div>
            <div class="stat-value">{@waypoint_count}</div>
            <div class="stat-desc"></div>
          </div>
          <div class="stat">
            <div class="stat-title">Markets</div>
            <div class="stat-value">{@market_count}</div>
            <div class="stat-desc"></div>
          </div>
          <div class="stat">
            <div class="stat-title">Shipyards</div>
            <div class="stat-value">{@shipyard_count}</div>
            <div class="stat-desc"></div>
          </div>
          <div class="stat">
            <div class="stat-title">Fleet in system</div>
            <div class="stat-value">{@fleet_in_system_count}</div>
            <div class="stat-desc">{@fleet_in_system_percent}% of {@fleet_total_count} total</div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  def mount(socket) do
    socket =
      socket
      |> assign(%{
        app_section: :galaxy
      })

    {:ok, socket}
  end

  def update(assigns, socket) do
    socket = assign(socket, assigns)

    agent_symbol = socket.assigns.agent.result.symbol
    system_symbol = socket.assigns.system_symbol

    system =
      Repo.get(System, system_symbol)
      |> Repo.preload(waypoints: [:traits])

    market_count =
      Enum.filter(system.waypoints, fn wp ->
        Enum.any?(wp.traits, fn t -> t.symbol == "MARKETPLACE" end)
      end)
      |> Enum.count()

    shipyard_count =
      Enum.filter(system.waypoints, fn wp ->
        Enum.any?(wp.traits, fn t -> t.symbol == "SHIPYARD" end)
      end)
      |> Enum.count()

    fleet_total_count =
      from(s in Ship,
        where: [agent_symbol: ^agent_symbol]
      )
      |> Repo.aggregate(:count)

    fleet_in_system_count =
      from(s in Ship,
        join: w in assoc(s, :nav_waypoint),
        where: [agent_symbol: ^agent_symbol],
        where: w.system_symbol == ^system_symbol
      )
      |> Repo.aggregate(:count)

    socket =
      socket
      |> assign(%{
        system: system,
        waypoint_count: Enum.count(system.waypoints),
        market_count: market_count,
        shipyard_count: shipyard_count,
        fleet_total_count: fleet_total_count,
        fleet_in_system_count: fleet_in_system_count,
        fleet_in_system_percent:
          Float.round(fleet_in_system_count / fleet_total_count * 100, 0) |> trunc()
      })

    {:ok, socket}
  end
end
