defmodule SpacetradersClientWeb.ShipComponent do
  use SpacetradersClientWeb, :live_component

  alias SpacetradersClient.ShipAutomaton
  alias SpacetradersClient.Game.Ship
  alias SpacetradersClient.Automation.ShipAutomationTick
  alias SpacetradersClient.Repo
  alias SpacetradersClientWeb.ShipStatsComponent

  import Ecto.Query, except: [update: 3]

  attr :client, :map, required: true
  attr :ship, :map, required: true
  attr :system, :map, default: nil
  attr :automaton, ShipAutomaton, default: nil

  def render(assigns) do
    ~H"""
    <section class="flex flex-col overflow-y-auto p-4">
      <header class="mb-4 flex-none">
        <h1 class="text-2xl font-bold"><%= @ship.symbol %></h1>
      </header>

      <section class="stats mb-8 flex-none">
        <ShipStatsComponent.registration ship={@ship} />
        <ShipStatsComponent.navigation ship={@ship} cooldown_remaining={@cooldown_remaining} />
        <ShipStatsComponent.fuel ship={@ship}>
          <div class="stat-actions">
            <button
              class="btn btn-neutral"
              phx-click="purchase-fuel"
              phx-value-ship-symbol={@ship.symbol}
            >
              Refuel
            </button>
          </div>
        </ShipStatsComponent.fuel>
        <ShipStatsComponent.cargo ship={@ship} />
      </section>


      <%= if @previous_automation_tick do %>
        <.live_component
          module={SpacetradersClientWeb.AutomatonComponent}
          id="automaton-#{@ship_symbol}"
          ship_automation_tick={@previous_automation_tick}
        />
      <% end %>

      <.tablist
        active_tab_id={@tab}
        target={@myself}
        tabs={[
          cargo: "Cargo",
          navigate: "Navigate",
          subsystems: "Subsystems",
          registration: "Registration"
        ]}
      />


      <section class="flex flex-col">
        <%= case @tab do %>
          <% :cargo -> %>
            <SpacetradersClientWeb.ShipCargoComponent.cargo ship={@ship} />
          <% :navigate -> %>
            <div>
              <div class="mb-8">
                <div class="font-bold text-lg mb-4">
                  Flight mode
                </div>

                <form phx-change="set-flight-mode" phx-value-ship-symbol={@ship.symbol}>
                  <select class="select select-bordered w-full max-w-xs" name="flight-mode">
                    <option value="BURN" selected={@ship.nav_flight_mode == :burn}>Burn</option>
                    <option value="CRUISE" selected={@ship.nav_flight_mode == :cruise}>Cruise</option>
                    <option value="DRIFT" selected={@ship.nav_flight_mode == :dift}>Drift</option>
                    <option value="STEALTH" selected={@ship.nav_flight_mode == :stealth}>Stealth</option>
                  </select>
                </form>
              </div>

              <div class="font-bold text-lg mb-4">
                Waypoints in this system
              </div>

              <div class="">
                <table class="table table-zebra">
                  <thead>
                    <tr>
                      <th>Symbol</th>
                      <th>Type</th>
                      <th></th>
                    </tr>
                  </thead>
                  <tbody>
                    <%= for waypoint <- @ship.nav_waypoint.system.waypoints do %>
                      <tr>
                        <td><%= waypoint.symbol %></td>
                        <td><%= waypoint.type %></td>
                        <td>

                          <% disabled = @ship.nav_status != :in_orbit %>

                          <div {if disabled, do: %{"class" => "tooltip", "data-tip" => "Ship must be undocked to travel"}, else: %{}}>
                            <button
                              class="btn btn-sm btn-accent"
                              phx-click="navigate-ship"
                              phx-value-ship-symbol={@ship.symbol}
                              phx-value-system-symbol={waypoint.system_symbol}
                              phx-value-waypoint-symbol={waypoint.symbol}
                              disabled={disabled}
                            >
                              Travel to
                            </button>
                          </div>
                        </td>
                      </tr>
                    <% end %>
                  </tbody>
                </table>
              </div>
            </div>

          <% :subsystems -> %>
            <div>
              Modules installed:
              <ul>
                <%= for module <- @ship["modules"] do %>
                  <li>
                    <p>
                      <%= module["name"] %>
                    </p>
                    <p class="text-sm">
                      <%= module["description"] %>
                    </p>
                  </li>
                <% end %>
              </ul>

              Mounts installed:
              <ul>
                <%= for mount <- @ship["mounts"] do %>
                  <li>
                    <p>
                      <%= mount["name"] %>
                    </p>
                    <div class="text-sm">
                      <p>
                        <%= mount["description"] %>
                      </p>
                      <%= if mount["deposits"] do %>
                        <p>Detects the following goods:</p>
                        <ul>
                          <%= for deposit <- mount["deposits"] do %>
                            <li><%= deposit %></li>
                          <% end %>
                        </ul>
                      <% end %>
                    </div>
                  </li>
                <% end %>
              </ul>
            </div>
          <% :registration -> %>
            <span>Registration here</span>
        <% end %>
      </section>
    </section>
    """
  end

  def mount(socket) do
    {:ok,
     assign(socket, %{
       tab: :cargo
     })}
  end

  def update(%{ship: ship}, socket) do
    ship =
      Repo.preload(ship, cargo_items: [:item], nav_waypoint: [system: [:waypoints]])

    ship_symbol = ship.symbol

    previous_automation_tick =
      Repo.one(
        from sat in ShipAutomationTick,
          where: [ship_symbol: ^ship_symbol],
          order_by: [desc: :timestamp],
          limit: 1,
          preload: [
            :ship,
            [
              active_task: [:float_args, :string_args, :decision_factors],
              alternative_tasks: [:float_args, :string_args, :decision_factors]
            ]
          ]
      )

    socket =
      assign(socket, %{
        ship_symbol: ship_symbol,
        ship: ship,
        previous_automation_tick: previous_automation_tick
      })

    socket =
      if socket.assigns[:ship] do
        socket
        |> assign(:cooldown_remaining, seconds_til_cooldown_expiration(socket.assigns[:ship]))
        |> schedule_cooldown_update()
      else
        socket
      end

    {:ok, socket}
  end

  def handle_event("select-tab", %{"tab" => tab}, socket) do
    socket =
      case tab do
        "cargo" ->
          assign(socket, :tab, :cargo)

        "navigate" ->
          assign(socket, :tab, :navigate)
      end

    {:noreply, socket}
  end

  def handle_async(:update_counter, _, socket) do
    socket =
      assign(socket, :cooldown_remaining, seconds_til_cooldown_expiration(socket.assigns.ship))

    socket = schedule_cooldown_update(socket)

    {:noreply, socket}
  end

  defp schedule_cooldown_update(socket) do
    if socket.assigns.cooldown_remaining > 0 do
      start_async(socket, :update_counter, fn ->
        Process.sleep(250)
        :ok
      end)
    else
      send(self(), {:travel_cooldown_expired, socket.assigns.ship.symbol})
      socket
    end
  end

  defp seconds_til_cooldown_expiration(ship) do
    if exp_at = ship.cooldown_expires_at do
      DateTime.diff(exp_at, DateTime.utc_now())
      |> max(0)
    else
      if arrive_at = ship.nav_route_arrival_at do
        DateTime.diff(arrive_at, DateTime.utc_now())
        |> max(0)
      else
        0
      end
    end
  end
end
