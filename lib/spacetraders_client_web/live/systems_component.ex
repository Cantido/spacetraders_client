defmodule SpacetradersClientWeb.SystemsComponent do
  use SpacetradersClientWeb, :live_component

  alias SpacetradersClient.Systems

  attr :agent, :map, default: nil
  attr :system_symbol, :string, default: nil
  attr :system, :map, default: nil
  attr :waypoint_symbol, :string, default: nil
  attr :waypoint, :map, default: nil
  attr :ship_symbol, :string, default: nil
  attr :fleet, :list
  attr :selected_ship, :map, default: nil

  def render(assigns) do
    ~H"""
    <section class="flex flex-row min-h-screen max-h-screen w-full">
      <div class="h-screen bg-base-200">
        <div class="w-80 max-h-full h-full flex flex-col">

            <h3 class="px-5 py-2 bg-neutral">
              <div class="breadcrumbs">
                <ul>
                  <li>
                    <.link
                      class="font-bold text-xl"
                      patch={~p"/game/systems/#{@system_symbol}"}
                    >
                      <%= @system_symbol %>
                    </.link>
                  </li>

                  <%= if @waypoint_symbol do %>
                    <li>
                      <div
                        class="font-bold text-xl"
                      >
                        <%= @waypoint_symbol %>
                      </div>
                    </li>
                  <% end %>
                </ul>
              </div>
            </h3>

          <.async_result :let={system} assign={@system}>
            <:loading><span class="loading loading-ring loading-lg"></span></:loading>
            <:failed :let={_failure}>There was an error loading the system.</:failed>

            <div class="overflow-auto">
              <SpacetradersClientWeb.OrbitalsMenuComponent.menu system={system} fleet={@fleet} />
            </div>
          </.async_result>
        </div>

      </div>

      <div class="m-8 w-full flex flex-col">
        <%= if @waypoint_symbol do %>
          <.async_result :let={waypoint} assign={@waypoint}>
            <:loading><span class="loading loading-ring loading-lg"></span></:loading>
            <:failed :let={_failure}>There was an error loading the waypoint.</:failed>

            <header class="mb-8">
              <h3 class="text-2xl font-bold"><%= @waypoint_symbol %></h3>
              <p class="text-lg text-neutral-500"><%= waypoint["type"] %></p>
            </header>

            <div role="tablist" class="tabs tabs-bordered mb-12 w-full">
              <a role="tab" class={if @waypoint_tab == "info", do: ["tab tab-active"], else: ["tab"]} phx-click="select-waypoint-tab" phx-value-waypoint-tab="info" phx-target={@myself}>Info</a>
              <a role="tab" class={if @waypoint_tab == "market", do: ["tab tab-active"], else: ["tab"]} phx-click="select-waypoint-tab" phx-value-waypoint-tab="market" phx-target={@myself}>Market</a>
              <a role="tab" class={if @waypoint_tab == "shipyard", do: ["tab tab-active"], else: ["tab"]} phx-click="select-waypoint-tab" phx-value-waypoint-tab="shipyard" phx-target={@myself}>Shipyard</a>
              <a role="tab" class={if @waypoint_tab == "chart", do: ["tab tab-active"], else: ["tab"]} phx-click="select-waypoint-tab" phx-value-waypoint-tab="chart" phx-target={@myself}>Chart</a>
            </div>

            <%= case @waypoint_tab do %>
              <% "info" -> %>
                <div class="flex justify-start gap-8 mb-8">
                  <section class="basis-56 grow min-w-56">
                    <SpacetradersClientWeb.WaypointInfoComponent.traits waypoint={waypoint} />
                  </section>

                  <section class="basis-56 grow min-w-56">
                    <SpacetradersClientWeb.WaypointInfoComponent.modifiers waypoint={waypoint} />
                  </section>
                </div>
                <div>
                  <div class="font-bold text-lg mb-4">
                  Ships at this waypoint
                  </div>
                  <table class="table table-zebra table-fixed">
                    <thead>
                      <tr>
                        <th>Name</th>
                        <th class="w-32">Role</th>
                        <th class="w-24">Status</th>
                        <th class="w-28">Condition</th>
                        <th class="w-28">Fuel</th>
                        <th>Actions</th>
                      </tr>
                    </thead>
                    <tbody>
                      <%= for ship <- Enum.filter(@fleet, fn ship -> ship["nav"]["waypointSymbol"] == @waypoint_symbol end) do %>
                        <tr>
                          <td><%= ship["registration"]["name"] %></td>
                          <td><%= ship["registration"]["role"] %></td>
                          <td>
                            <%= ship["nav"]["status"] %>
                          </td>
                          <td><%= condition_percentage(ship) %>%</td>
                          <td>
                            <%= if ship["fuel"]["capacity"] > 0 do %>
                              <%= trunc(Float.round(ship["fuel"]["current"] / ship["fuel"]["capacity"] * 100)) %>%
                            <% else %>
                              <span class="opacity-50 italic">No fuel tank</span>
                            <% end %>
                          </td>
                          <td class="flex gap-3">
                            <button
                              class="btn btn-sm"
                              disabled={ship["nav"]["status"] != "DOCKED" || ship["fuel"]["capacity"] in [0, nil]}
                            >
                              Refuel
                            </button>

                            <button
                              class="btn btn-sm"
                              phx-click="show-repair-modal"
                              disabled={ship["nav"]["status"] != "DOCKED" ||  condition_percentage(ship) == 100}
                            >
                              Repair
                            </button>
                            <div class="join">
                              <button
                                class="btn btn-sm btn-accent join-item"
                                phx-click="orbit-ship"
                                phx-value-ship-symbol={ship["symbol"]}
                                disabled={ship["nav"]["status"] in ["IN_ORBIT", "IN_TRANSIT"]}
                              >
                                Undock
                              </button>
                              <button
                                class="btn btn-sm btn-accent join-item"
                                phx-click="dock-ship"
                                phx-value-ship-symbol={ship["symbol"]}
                                disabled={ship["nav"]["status"] in ["DOCKED", "IN_TRANSIT"]}
                              >
                                Dock
                              </button>
                            </div>
                          </td>
                        </tr>
                      <% end %>
                    </tbody>
                  </table>
                </div>
              <% "market" -> %>
                <.async_result :let={market} assign={@market}>
                  <.live_component
                    module={SpacetradersClientWeb.WaypointMarketComponent}
                    id={"market-#{waypoint["symbol"]}"}
                    client={@client}
                    market={market}
                    system_symbol={waypoint["systemSymbol"]}
                    waypoint_symbol={waypoint["symbol"]}
                />
                <% ship = Enum.find(@fleet, &(&1["symbol"] == @selected_ship["symbol"])) %>
              </.async_result>

              <% "shipyard" -> %>
                Shipyard go here

              <% "chart" -> %>
                Chart go here

            <% end %>
          </.async_result>
        <% else %>
          <div class="mb-8">
            <%= if @system_symbol do %>
              <p class="text-lg text-neutral-500">System</p>
              <h3 class="text-2xl font-bold"><%= @system_symbol %></h3>
            <% else %>
              Select a system or waypoint.
            <% end %>
          </div>
        <% end %>
      </div>


      <SpacetradersClientWeb.RefuelModalComponent.modal
        client={@client}
        available_funds={@agent["credits"]}
        fuel_price={100}
        ship={@selected_ship}
      />

    </section>

    """
  end

  def mount(socket) do
    {:ok, assign(socket, :waypoint_tab, "info")}
  end

  def update(assigns, socket) do
    socket = assign(socket, assigns)

    socket =
      if symbol = socket.assigns[:system_symbol] do
        client = socket.assigns.client
        assign_async(socket, :system, fn ->
          case Systems.get_system(client, symbol) do
            {:ok, %{status: 200, body: body}} ->
              system =
                body["data"]
                |> Map.update!("waypoints", fn waypoints ->
                  Enum.sort_by(waypoints, &(&1["symbol"]))
                end)

              {:ok, %{system: system}}
            {:ok, resp} ->
              {:error, resp}
            err ->
              err
          end
        end)
      else
        socket
      end

    socket =
      if waypoint_symbol = socket.assigns[:waypoint_symbol] do
        client = socket.assigns.client
        system_symbol = socket.assigns.system_symbol

        assign_async(socket, :waypoint, fn ->
          case Systems.get_waypoint(client, system_symbol, waypoint_symbol) do
            {:ok, %{status: 200, body: body}} ->
              {:ok, %{waypoint: body["data"]}}
            {:ok, resp} ->
              {:error, resp}
            err ->
              err
          end
        end)
        |> assign_async(:market, fn ->
          {:ok, %{status: 200, body: body}} = Systems.get_market(client, system_symbol, waypoint_symbol)

          {:ok, %{market: body["data"]}}
        end)
      else
        assign(socket, :waypoint, nil)
      end


    {:ok, socket}
  end

  def handle_event("select-waypoint-tab", %{"waypoint-tab" => waypoint_tab}, socket) do
    {:noreply, assign(socket, :waypoint_tab, waypoint_tab)}
  end

  defp condition_percentage(ship) do
    (
      ship["frame"]["condition"] +
        ship["reactor"]["condition"] +
        ship["engine"]["condition"]
    )
    |> then(fn sum ->
      sum / 3 * 100
    end)
    |> Float.round(0)
    |> trunc()
  end

  defp fuel_price(market) do
    Enum.find(market["tradeGoods"], fn %{"symbol" => symbol} -> symbol == "FUEL" end)
    |> Map.get("purchasePrice")
  end
end
