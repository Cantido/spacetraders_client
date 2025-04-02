defmodule SpacetradersClientWeb.MapComponent do
  use SpacetradersClientWeb, :live_component

  alias SpacetradersClient.Repo

  attr :system, :map, required: true
  attr :waypoint_symbol, :string, default: nil

  def render(assigns) do
    ~H"""
    <div class="w-full h-full relative">
      <div
        id="system-map"
        class="w-full h-full"
        phx-hook="SystemMap"
        data-system={Jason.encode!(@system)}
        data-waypoint-symbol={Jason.encode!(@waypoint_symbol)}
      ></div>
    </div>
    """
  end

  def update(assigns, socket) do
    system =
      assigns.system
      |> Repo.preload(waypoints: [:modifiers, :traits])

    {:ok, assign(socket, :system, system)}
  end
end
