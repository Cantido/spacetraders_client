defmodule SpacetradersClientWeb.ShipComponent do
  alias SpacetradersClientWeb.ShipStatsComponent
  use SpacetradersClientWeb, :live_component

  alias SpacetradersClient.Systems

  def render(assigns) do
    ~H"""
    <section class="p-8 w-full flex flex-col overflow-y-auto">
      <header class="mb-4 flex-none">
        <h1 class="text-2xl font-bold"><%= @ship["registration"]["name"] %></h1>
      </header>

      <section class="stats mb-8 flex-none">
        <ShipStatsComponent.registration ship={@ship} />
        <ShipStatsComponent.navigation ship={@ship} cooldown_remaining={@cooldown_remaining} />
        <ShipStatsComponent.fuel ship={@ship}>
          <div class="stat-actions">
            <button
              class="btn btn-neutral"
              phx-click="purchase-fuel"
              phx-value-ship-symbol={@ship["symbol"]}
            >
              Refuel
            </button>
          </div>
        </ShipStatsComponent.fuel>
        <ShipStatsComponent.cargo ship={@ship} />
      </section>

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

                <form phx-change="set-flight-mode" phx-value-ship-symbol={@ship["symbol"]}>
                  <select class="select select-bordered w-full max-w-xs" name="flight-mode">
                    <option value="BURN" selected={@ship["nav"]["flightMode"] == "BURN"}>Burn</option>
                    <option value="CRUISE" selected={@ship["nav"]["flightMode"] == "CRUISE"}>Cruise</option>
                    <option value="DRIFT" selected={@ship["nav"]["flightMode"] == "DRIFT"}>Drift</option>
                    <option value="STEALTH" selected={@ship["nav"]["flightMode"] == "STEALTH"}>Stealth</option>
                  </select>
                </form>
              </div>

              <div class="font-bold text-lg mb-4">
                Waypoints in this system
              </div>

              <div class="">
                <.async_result :let={system} assign={@system}>
                  <:loading><span class="loading loading-ring loading-lg"></span></:loading>
                  <:failed :let={_failure}>There was an error loading the system.</:failed>

                  <table class="table table-zebra">
                    <thead>
                      <tr>
                        <th>Symbol</th>
                        <th>Type</th>
                        <th></th>
                      </tr>
                    </thead>
                    <tbody>
                      <%= for waypoint <- system["waypoints"] do %>
                        <tr>
                          <td><%= waypoint["symbol"] %></td>
                          <td><%= waypoint["type"] %></td>
                          <td>

                            <% disabled = @ship["nav"]["status"] != "IN_ORBIT" %>

                            <div {if disabled, do: %{"class" => "tooltip", "data-tip" => "Ship must be undocked to travel"}, else: %{}}>
                              <button
                                class="btn btn-sm btn-accent"
                                phx-click="navigate-ship"
                                phx-value-ship-symbol={@ship["symbol"]}
                                phx-value-system-symbol={waypoint["systemSymbol"]}
                                phx-value-waypoint-symbol={waypoint["symbol"]}
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
                </.async_result>
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
    {:ok, assign(socket, %{
      tab: :cargo
    })}
  end

  def update(assigns, socket) do
    socket = assign(socket, assigns)

    socket =
      if socket.assigns[:ship] do
        socket
        |> assign(:cooldown_remaining, seconds_til_cooldown_expiration(socket.assigns[:ship]))
        |> schedule_cooldown_update()
      else
        socket
      end

    socket =
      if socket.assigns[:tab] == :waypoint do
        client = socket.assigns.client
        system_symbol = socket.assigns.ship["nav"]["systemSymbol"]
        waypoint_symbol = socket.assigns.ship["nav"]["waypointSymbol"]

        assign_async(socket, :waypoint, fn ->
          case Systems.get_waypoint(client, system_symbol, waypoint_symbol) do
            {:ok, %{status: 200, body: body}} ->
              {:ok, %{waypoint: body["data"]}}
            err ->
              err
          end
        end)
      else
        socket
      end

    {:ok, socket}

  end

  def handle_event("select-tab", %{"tab" => tab}, socket) do
    {:noreply, assign(socket, :tab, String.to_existing_atom(tab))}
  end

  def handle_async(:update_counter, _, socket) do
    socket = assign(socket, :cooldown_remaining, seconds_til_cooldown_expiration(socket.assigns.ship))
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
      send self(), {:travel_cooldown_expired, socket.assigns.ship["symbol"]}
      socket
    end
  end

  defp seconds_til_cooldown_expiration(ship) do
    if cooldown = ship["cooldown"]["expiration"] do
      {:ok, exp_at, _} = DateTime.from_iso8601(cooldown)

      DateTime.diff(exp_at, DateTime.utc_now())
      |> max(0)
    else
      if arrival_ts = ship["nav"]["route"]["arrival"] do
        {:ok, arrive_at, _} = DateTime.from_iso8601(arrival_ts)

        DateTime.diff(arrive_at, DateTime.utc_now())
        |> max(0)
      else
        0
      end
    end
  end
end
