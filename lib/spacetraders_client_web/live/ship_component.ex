defmodule SpacetradersClientWeb.ShipComponent do
  use SpacetradersClientWeb, :live_component

  alias SpacetradersClient.ShipAutomaton
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
        <h1 class="text-2xl font-bold">
          <%= @ship.symbol %>
          <button class="inline-block btn btn-square btn-sm" phx-click="reload-ship" phx-value-ship-symbol={@ship.symbol}>
            <Heroicons.arrow_path mini class="h-4 w-4 inline-block text-error" />
          </button>
        </h1>

        <span class="opacity-50 text-xl font-normal">
          {@ship.registration_role} ship

          <%= case @ship.nav_status do %>
            <% :docked -> %>
              docked at
              <.link patch={~p"/game/systems/#{@ship.nav_waypoint.symbol}"} class="link">{@ship.nav_waypoint.symbol}</.link>
            <% :in_orbit -> %>
              in orbit around
              <.link patch={~p"/game/systems/#{@ship.nav_waypoint.symbol}"} class="link">{@ship.nav_waypoint.symbol}</.link>
            <% :in_transit -> %>
              in transit to
              <.link patch={~p"/game/systems/#{@ship.nav_waypoint.symbol}"} class="link">{@ship.nav_waypoint.symbol}</.link>
          <% end %>
        </span>
      </header>

      <section class="stats mb-8 flex-none">
        <ShipStatsComponent.navigation ship={@ship} now={@stats_timestamp} />
        <ShipStatsComponent.cooldown ship={@ship} now={@stats_timestamp} />
        <ShipStatsComponent.fuel ship={@ship}>
          <div class="stat-actions">
            <button
              class="btn btn-neutral btn-xs"
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

      <div>
        <.radio_tablist name="ship-tabs-#{@ship.symbol}" class="tabs-lift">
          <:tab label="Cargo" active={true} class="border-base-300">
            <SpacetradersClientWeb.ShipCargoComponent.cargo ship={@ship} />
          </:tab>
          <:tab label="Navigate" class="border-base-300">
            <div class="">
              <div class="mb-8 p-4">
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

              <div class="font-bold text-lg mb-4 p-4">
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
                      <% waypoint = Repo.preload(waypoint, :system) %>
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
                              phx-value-system-symbol={waypoint.system.symbol}
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
          </:tab>
          <:tab label="Subsystems" class="border-base-300">
            <div class="p-2">Subsystems here</div>
          </:tab>
          <:tab label="Registration" class="border-base-300">
            <div class="p-2">Registration here</div>
          </:tab>
        </.radio_tablist>
      </div>
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
          where: [ship_id: ^ship.id],
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
        previous_automation_tick: previous_automation_tick,
        stats_timestamp: DateTime.utc_now()
      })
      |> start_async(:tick_stats, fn ->
        Process.sleep(250)

        :ok
      end)

    {:ok, socket}
  end

  def handle_async(:tick_stats, _, socket) do
    socket =
      socket
      |> assign(:stats_timestamp, DateTime.utc_now())
      |> start_async(:tick_stats, fn ->
        Process.sleep(250)

        :ok
      end)

    {:noreply, socket}
  end
end
