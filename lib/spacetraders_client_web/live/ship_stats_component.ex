defmodule SpacetradersClientWeb.ShipStatsComponent do
  use SpacetradersClientWeb, :html

  attr :ship, :map, required: true

  def registration(assigns) do
    ~H"""
    <div class="stat">
      <h3 class="stat-title">Role</h3>
      <div class="stat-value"><%= @ship["registration"]["role"] %></div>
      <div class="stat-desc invisible"></div>
      <div class="stat-actions invisible">
        <button class="btn btn-neutral" disabled></button>
      </div>
    </div>
    """
  end

  attr :ship, :map, required: true
  attr :cooldown_remaining, :integer, default: 0

  def navigation(assigns) do
  ~H"""
  <div class="stat">
    <h3 class="stat-title">Navigation</h3>
    <%= case @ship["nav"]["status"] do %>
      <% "IN_TRANSIT" -> %>
        <div class="stat-figure">
          <div class="radial-progress" style={"--value:#{transit_complete_percentage(@ship, @cooldown_remaining)};"} role="progressbar">
            <div class="countdown font-mono ">
              <span style={"--value:#{trunc(@cooldown_remaining / 60)};"}></span>
              :
              <span style={"--value:#{Integer.mod(@cooldown_remaining, 60)};"}></span>
            </div>
          </div>
        </div>
        <div class="stat-value">
          In transit
        </div>
        <div class="stat-desc">
          <% waypoint_symbol = get_in(@ship, ~w(nav route destination symbol)) %>
          <%= @ship["nav"]["flightMode"] %> to
          <.link
            class="link"
            patch={~p"/game/systems/#{@ship["nav"]["systemSymbol"]}/waypoints/#{waypoint_symbol}"}
          >
            <%= waypoint_symbol %>
          </.link>
        </div>
        <div class="stat-actions">
          <button class="btn btn-neutral" disabled>Undock</button>
          <button class="btn btn-neutral" disabled>Dock</button>
        </div>
      <% "IN_ORBIT" -> %>
        <div class="stat-value">
          In orbit
        </div>
        <div class="stat-desc">
          Orbiting
          <.link
            class="link"
            patch={~p"/game/systems/#{@ship["nav"]["systemSymbol"]}/waypoints/#{@ship["nav"]["waypointSymbol"]}"}
          >
            <%= get_in(@ship, ~w(nav waypointSymbol)) %>
          </.link>
        </div>
        <div class="stat-actions">
          <button class="btn btn-neutral" disabled>Undock</button>
          <button phx-click="dock-ship" phx-value-ship-symbol={@ship["symbol"]} class="btn btn-neutral">Dock</button>
        </div>
      <% "DOCKED" -> %>
        <div class="stat-value">
          Docked
        </div>
        <div class="stat-desc">
          Docked at
          <.link
            class="link"
            patch={~p"/game/systems/#{@ship["nav"]["systemSymbol"]}/waypoints/#{@ship["nav"]["waypointSymbol"]}"}
          >
            <%= get_in(@ship, ~w(nav waypointSymbol)) %>
          </.link>
        </div>
        <div class="stat-actions">
          <button phx-click="orbit-ship" phx-value-ship-symbol={@ship["symbol"]} class="btn btn-neutral">Undock</button>
          <button class="btn btn-neutral" disabled>Dock</button>
        </div>
    <% end %>
  </div>
  """
  end

  attr :ship, :map, required: true
  slot :inner_block

  def fuel(assigns) do
    ~H"""
    <div class="stat">
      <%
        fuel_current = @ship["fuel"]["current"]
        fuel_capacity = @ship["fuel"]["capacity"]
        fuel_percent = if fuel_capacity > 0, do: trunc(Float.ceil(fuel_current / fuel_capacity * 100)), else: 100
      %>

      <h3 class="stat-title">Fuel</h3>
      <div class="stat-value">
        <%= if fuel_capacity == 0 do %>
          <span>No tank</span>
        <% else %>
          <span><%= fuel_current %>u</span>
        <% end %>
      </div>
      <div class="stat-figure">
        <div class="radial-progress" style={"--value:#{fuel_percent};"} role="progressbar"><%= fuel_percent%>%</div>
      </div>
      <div class="stat-desc">
        <div>Capacity of <%= fuel_capacity %>u</div>
      </div>

      <%= render_slot(@inner_block) %>
    </div>
    """
  end

  def cargo(assigns) do
    ~H"""
    <div class="stat">
      <%
        cargo_current = get_in(@ship, ~w(cargo units))
        cargo_capacity = get_in(@ship, ~w(cargo capacity))
        cargo_percent = if is_integer(cargo_capacity) && cargo_capacity > 0, do: trunc(Float.ceil(cargo_current / cargo_capacity * 100)), else: 0
      %>
      <h3 class="stat-title">Cargo</h3>
      <div class="stat-value">
        <%= cargo_current %>u
      </div>
      <div class="stat-figure">
        <div class="radial-progress" style={"--value:#{cargo_percent};"} role="progressbar"><%= cargo_percent %>%</div>
      </div>
      <div class="stat-desc">
        <div>Capacity of <%= cargo_capacity %>u</div>
      </div>
      <div class="stat-actions invisible">
        <button class="btn btn-neutral" disabled></button>
      </div>
    </div>
    """
  end


  def transit_complete_percentage(ship, _cooldown_remaining) do
    {:ok, departure, _} = DateTime.from_iso8601(ship["nav"]["route"]["departureTime"])
    {:ok, arrival, _} = DateTime.from_iso8601(ship["nav"]["route"]["arrival"])
    now = DateTime.utc_now()

    total_duration = DateTime.diff(arrival, departure)
    remaining_duration = DateTime.diff(arrival, now)

    if remaining_duration >= 0 do
      remaining_duration / total_duration * 100
    else
      100
    end
  end
end
