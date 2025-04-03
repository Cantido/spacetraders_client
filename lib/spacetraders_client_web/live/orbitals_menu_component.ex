defmodule SpacetradersClientWeb.OrbitalsMenuComponent do
  use SpacetradersClientWeb, :live_component

  alias SpacetradersClient.Game.System
  alias SpacetradersClient.Game.Market
  alias SpacetradersClient.Game.Waypoint
  alias SpacetradersClient.Game.Shipyard
  alias SpacetradersClient.Game.Ship
  alias SpacetradersClient.Repo
  alias Phoenix.LiveView.AsyncResult
  alias Phoenix.PubSub

  import Ecto.Query, except: [update: 3]

  @pubsub SpacetradersClient.PubSub

  attr :system_symbol, :string, required: true
  attr :waypoint_symbol, :string, default: nil

  slot :inner_block

  def render(assigns) do
    ~H"""
    <div class="drawer drawer-open">
      <input id="waypoints-drawer" type="checkbox" class="drawer-toggle" />
      <div class="drawer-side">
        <.async_result :let={system} assign={@system}>
          <:loading>
            <div class="w-72 h-full">
              <div class="bg-neutral-600 h-24 p-4">
                <div class="skeleton h-6 w-full bg-neutral-700 mb-2"></div>
                <div class="skeleton h-5 w-24 bg-neutral-700"></div>
              </div>
              <div class="bg-base-200 skeleton rounded-none h-full"></div>
            </div>
          </:loading>
          <:failed :let={_failure}>There was an error loading the system.</:failed>

          <div class="w-72">
            <div class="bg-neutral-600 p-4 h-24 hover:link">
              <.link patch={~p"/game/systems/#{system.symbol}"}>
                <h1 class="text-xl font-bold bg-neutral-600">{system.name}</h1>
              </.link>
              <span class="text-sm font-mono">
                {system.symbol}
              </span>
            </div>
            <.menu
              :let={waypoint_symbol}
              system={system}
              active_waypoint={@waypoint_symbol}
              class="bg-base-200 w-72"
            >
              <:additional_waypoint_items :let={waypoint_symbol}>
                <.async_result :let={fleet} assign={@fleet}>
                  <:loading></:loading>
                  <:failed :let={_failure}></:failed>
                  <li
                    :for={
                      ship <-
                        Enum.filter(fleet, fn ship ->
                          ship.nav_waypoint.symbol == waypoint_symbol
                        end)
                    }
                    class=""
                  >
                    <.link patch={~p"/game/fleet/#{ship.symbol}"} class="">
                      <Heroicons.rocket_launch solid class="w-6 h-6 text-primary" />
                      {ship.symbol}
                    </.link>
                  </li>
                </.async_result>
              </:additional_waypoint_items>
              <.waypoint_item
                symbol={waypoint_symbol}
                type={Enum.find(system.waypoints, fn wp -> wp.symbol == waypoint_symbol end).type}
              >
                <:indicator>
                  <.async_result :let={shipyards} assign={@shipyards}>
                    <:loading><span class="loading loading-ring loading-lg"></span></:loading>
                    <:failed :let={_failure}>There was an error loading shipyards.</:failed>
                    <span
                      :if={Enum.any?(shipyards, fn s -> s.symbol == waypoint_symbol end)}
                      class="tooltip tooltip-left tooltip-info"
                      data-tip="This waypoint has a shipyard"
                    >
                      <Heroicons.wrench_screwdriver mini class="mr-1 w-4 h-4 aspect-square" />
                    </span>
                  </.async_result>
                </:indicator>
                <:indicator>
                  <.async_result :let={marketplaces} assign={@marketplaces}>
                    <:loading><span class="loading loading-ring loading-lg"></span></:loading>
                    <:failed :let={_failure}>There was an error loading marketplaces.</:failed>
                    <span
                      :if={Enum.any?(marketplaces, fn m -> m.symbol == waypoint_symbol end)}
                      class="tooltip tooltip-left tooltip-info"
                      data-tip="This waypoint has a marketplace"
                    >
                      <Heroicons.building_storefront mini class="mr-1 w-4 h-4 aspect-square" />
                    </span>
                  </.async_result>
                </:indicator>
              </.waypoint_item>
            </.menu>
          </div>
        </.async_result>
      </div>

      <div class="drawer-content">
        {render_slot(@inner_block)}
      </div>
    </div>
    """
  end

  attr :system, System, required: true
  attr :active_waypoint, :string, default: nil
  attr :class, :string, default: nil

  slot :inner_block, required: true
  slot :additional_waypoint_items

  def menu(assigns) do
    section_types = [
      %{name: "Planets", types: ~w(PLANET)},
      %{name: "Gas giants", types: ~w(GAS_GIANT)},
      %{name: "Orbital stations", types: ~w(ORBITAL_STATION)},
      %{name: "Jump gates", types: ~w(JUMP_GATE)},
      %{name: "Asteroids", types: ~w(ASTEROID ENGINEERED_ASTEROID ASTEROID_BASE)}
    ]

    type_sections =
      Enum.flat_map(section_types, fn %{name: name, types: types} ->
        Enum.map(types, fn type ->
          {type, name}
        end)
      end)
      |> Map.new()

    section_waypoints =
      get_primary_satellites(assigns.system)
      |> Enum.reduce(%{}, fn wp, sections_acc ->
        if section_name = Map.get(type_sections, wp.type) do
          sections_acc
          |> Map.put_new(section_name, [])
          |> Map.update!(section_name, &[wp | &1])
        else
          sections_acc
        end
      end)

    assigns = assign(assigns, :section_types, section_types)
    assigns = assign(assigns, :section_waypoints, section_waypoints)

    ~H"""
    <ul class={["menu", @class]}>
      <%= for %{name: section_name} <- @section_types do %>
        <% in_section =
          Map.get(@section_waypoints, section_name, []) |> Enum.sort_by(fn wp -> wp.symbol end) %>
        <%= if Enum.any?(in_section) do %>
          <li>
            <details open>
              <summary class="bg-base-300 font-bold my-2">{section_name}</summary>
              <ul>
                <%= for waypoint <- in_section do %>
                  <.submenu
                    system={@system}
                    waypoint_symbol={waypoint.symbol}
                    active_waypoint={@active_waypoint}
                  >
                    <:additional_items :let={waypoint_symbol}>
                      {render_slot(@additional_waypoint_items, waypoint_symbol)}
                    </:additional_items>
                    <:link_content :let={waypoint_symbol}>
                      {render_slot(@inner_block, waypoint_symbol)}
                    </:link_content>
                  </.submenu>
                <% end %>
              </ul>
            </details>
          </li>
        <% end %>
      <% end %>
    </ul>
    """
  end

  attr :system, :map, required: true
  attr :waypoint_symbol, :string, required: true
  attr :active_waypoint, :string, default: nil

  slot :link_content, required: true
  slot :additional_items

  defp submenu(assigns) do
    ~H"""
    <li class="my-1">
      <.link
        patch={~p"/game/systems/#{@system.symbol}/waypoints/#{@waypoint_symbol}"}
        class={if @active_waypoint == @waypoint_symbol, do: ["menu-active"], else: []}
      >
        {render_slot(@link_content, @waypoint_symbol)}
      </.link>
      <ul>
        {render_slot(@additional_items, @waypoint_symbol)}
        <%= for waypoint <- get_satellites(@system, @waypoint_symbol) do %>
          <.submenu
            system={@system}
            waypoint_symbol={waypoint.symbol}
            active_waypoint={@active_waypoint}
          >
            <:additional_items :let={additional_wp_symbol}>
              {render_slot(@additional_items, additional_wp_symbol)}
            </:additional_items>
            <:link_content :let={waypoint_symbol}>
              {render_slot(@link_content, waypoint_symbol)}
            </:link_content>
          </.submenu>
        <% end %>
      </ul>
    </li>
    """
  end

  defp get_primary_satellites(system) do
    Enum.filter(system.waypoints, fn wp -> is_nil(wp.orbits) end)
  end

  defp get_satellites(system, waypoint_symbol) do
    Enum.filter(system.waypoints, fn wp -> wp.orbits_waypoint.symbol == waypoint_symbol end)
  end

  attr :type, :string, required: true

  def waypoint_icon(assigns) do
    ~H"""
    <%= case @type do %>
      <% "PLANET" -> %>
        <.icon name="game-world" size={24} />
      <% "GAS_GIANT" -> %>
        <.icon name="game-jupiter" size={24} />
      <% "MOON" -> %>
        <.icon name="game-moon-orbit" size={24} />
      <% "ORBITAL_STATION" -> %>
        <.icon name="game-defense-satellite" size={24} />
      <% "JUMP_GATE" -> %>
        <.icon name="game-vortex" />
      <% "ASTEROID_FIELD" -> %>
        <.icon name="game-star-swirl" size={24} />
      <% "ASTEROID" -> %>
        <.icon name="game-asteroid" size={24} />
      <% "ENGINEERED_ASTEROID" -> %>
        <.icon name="game-death-star" size={24} />
      <% "ASTEROID_BASE" -> %>
        <.icon name="game-lunar-module" size={24} />
      <% _ -> %>
        <.icon name="game-orbital" size={24} />
    <% end %>
    """
  end

  attr :symbol, :string, required: true
  attr :type, :string, required: true

  slot :indicator

  def waypoint_item(assigns) do
    ~H"""
    <.waypoint_icon type={@type} />
    <span class="flex flex-row items-center justify-between">
      <span>{@symbol}</span>

      <span>
        <span :for={icon <- @indicator} class="w-4">
          {render_slot(icon)}
        </span>
      </span>
    </span>
    """
  end

  def mount(socket) do
    {:ok, socket}
  end

  def update(assigns, socket) do
    socket = assign(socket, assigns)

    PubSub.subscribe(@pubsub, "agent:#{socket.assigns.agent_symbol}")

    markets =
      Repo.all(
        from m in Market,
          join: w in Waypoint,
          on: m.symbol == w.symbol,
          join: s in assoc(w, :system),
          where: s.symbol == ^socket.assigns.system_symbol
      )

    shipyards =
      Repo.all(
        from s in Shipyard,
          join: w in Waypoint,
          on: s.symbol == w.symbol,
          join: sys in assoc(w, :system),
          where: sys.symbol == ^socket.assigns.system_symbol
      )

    system =
      Repo.get_by(System, symbol: socket.assigns.system_symbol)
      |> Repo.preload(waypoints: [:orbits, :orbitals])

    fleet =
      Repo.all(
        from s in Ship,
          where: [agent_symbol: ^socket.assigns.agent_symbol],
          preload: [:nav_waypoint]
      )

    socket =
      socket
      |> assign(%{
        shipyards: AsyncResult.ok(shipyards),
        marketplaces: AsyncResult.ok(markets),
        system: AsyncResult.ok(system),
        fleet: AsyncResult.ok(fleet)
      })

    {:ok, socket}
  end

  def handle_info(:fleet_updated, socket) do
    fleet =
      Repo.all(
        from s in Ship,
          where: [agent_symbol: ^socket.assigns.agent_symbol],
          preload: [:nav_waypoint]
      )

    socket =
      socket
      |> assign(%{
        fleet: AsyncResult.ok(fleet)
      })

    {:noreply, socket}
  end

  def handle_info({:ship_updated, _symbol}, socket) do
    fleet =
      Repo.all(
        from s in Ship,
          where: [agent_symbol: ^socket.assigns.agent_symbol],
          preload: [:nav_waypoint]
      )

    socket =
      socket
      |> assign(%{
        fleet: AsyncResult.ok(fleet)
      })

    {:noreply, socket}
  end

  def handle_info({:ship_updated, _symbol, _ship}, socket) do
    fleet =
      Repo.all(
        from s in Ship,
          where: [agent_symbol: ^socket.assigns.agent_symbol],
          preload: [:nav_waypoint]
      )

    socket =
      socket
      |> assign(%{
        fleet: AsyncResult.ok(fleet)
      })

    {:noreply, socket}
  end

  def handle_info(_, socket) do
    {:noreply, socket}
  end
end
