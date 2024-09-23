defmodule SpacetradersClientWeb.OrbitalsMenuComponent do
  use SpacetradersClientWeb, :html

  attr :fleet, :list, required: true
  attr :system, :map, required: true
  attr :active_waypoint, :string, default: nil

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
      get_orbiting_waypoint(assigns.system, nil)
      |> Enum.reduce(%{}, fn wp, sections_acc ->
        if section_name = Map.get(type_sections, wp["type"]) do
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
    <div>
      <ul class="menu">
        <%= for %{name: section_name} <- @section_types do %>
          <% in_section = Map.get(@section_waypoints, section_name, []) %>
          <%= if Enum.any?(in_section) do %>
            <li>
              <details open>
                <summary class="bg-base-100"><%= section_name %></summary>
                <ul>
                  <%= for waypoint <- in_section do %>
                    <.submenu fleet={@fleet} system={@system} waypoint={waypoint} />
                  <% end %>
                </ul>
              </details>
            </li>
          <% end %>
        <% end %>
      </ul>
    </div>
    """
  end

  attr :system, :map, required: true
  attr :waypoint, :map, required: true
  attr :fleet, :list, required: true
  attr :active, :boolean, default: false

  defp submenu(assigns) do
    ~H"""
    <li>
      <.link
        patch={~p"/game/systems/#{@system["symbol"]}/waypoints/#{@waypoint["symbol"]}"}
        class={if @active, do: ["active"], else: []}
      >
        <%= case @waypoint["type"] do %>
          <% "PLANET" -> %>
            <.icon name="game-world" />
          <% "GAS_GIANT" -> %>
            <.icon name="game-jupiter" />
          <% "MOON" -> %>
            <.icon name="game-moon-orbit" />
          <% "ORBITAL_STATION" -> %>
            <.icon name="game-defense-satellite" />
          <% "JUMP_GATE" -> %>
            <.icon name="game-vortex" />
          <% "ASTEROID_FIELD" -> %>
            <.icon name="game-star-swirl" />
          <% "ASTEROID" -> %>
            <.icon name="game-asteroid" />
          <% "ENGINEERED_ASTEROID" -> %>
            <.icon name="game-death-star" />
          <% "ASTEROID_BASE" -> %>
            <.icon name="game-lunar-module" />
          <% _ -> %>
            <.icon name="game-orbital" />
        <% end %>
        <%= @waypoint["symbol"] %>

        <%= if Enum.any?(@fleet, fn ship -> ship["nav"]["waypointSymbol"] == @waypoint["symbol"] end) do %>
          <span class="tooltip tooltip-left tooltip-accent" data-tip="You have ships here">
            <span class="badge badge-xs badge-accent" ></span>
          </span>
        <% end %>
      </.link>
      <ul>
        <%= for waypoint <- get_orbiting_waypoint(@system, @waypoint["symbol"]) do %>
          <.submenu fleet={@fleet} system={@system} waypoint={waypoint} />
        <% end %>
      </ul>
    </li>
    """
  end

  defp get_orbiting_waypoint(system, waypoint_symbol) do
    Enum.filter(system["waypoints"], fn waypoint ->
      waypoint["orbits"] == waypoint_symbol
    end)
  end

  defp filter_waypoints_by_type(waypoints, type) do
    Enum.filter(waypoints, fn wp ->
      wp["type"] =~ type
    end)
  end
end
