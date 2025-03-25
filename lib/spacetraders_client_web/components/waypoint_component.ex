defmodule SpacetradersClientWeb.WaypointComponent do
  use SpacetradersClientWeb, :live_component

  alias SpacetradersClient.Systems
  alias Phoenix.LiveView.AsyncResult
  alias Phoenix.PubSub
  alias SpacetradersClient.Agents
  alias SpacetradersClient.AutomationServer
  alias SpacetradersClient.Client
  alias SpacetradersClient.Fleet
  alias SpacetradersClient.ShipAutomaton

  @pubsub SpacetradersClient.PubSub

  attr :waypoint_symbol, :string, required: true
  attr :contracts, :list, default: []
  attr :ships_at_waypoint, :list, default: []
  attr :fleet, :list, default: []

  def render(assigns) do
    ~H"""
    <div class="p-4">

      <.async_result :let={waypoint} assign={@waypoint}>
        <:loading><span class="loading loading-ring loading-lg"></span></:loading>
        <:failed :let={_failure}>There was an error loading the waypoint.</:failed>

        <header class="mb-2">
          <h1 class="text-2xl font-bold mb-2">
            <%= waypoint["symbol"] %>
          </h1>

          <span class="opacity-50 text-xl font-normal">
            <%= waypoint["type"] %>
            in

            <.async_result :let={system} assign={@system}>
              <:loading><div class="skeleton h-6 w-56 inline-block align-middle"></div></:loading>
              <:failed :let={_failure}>
                an unknown system
              </:failed>
              the
              <.link patch={~p"/game/systems/#{system["symbol"]}"} class="link">{system["name"]}</.link>
              system
            </.async_result>

          </span>

        </header>

        <div class="mb-4">
          <SpacetradersClientWeb.WaypointInfoComponent.traits waypoint={waypoint} />
        </div>
        <div class="mb-4">

          <%
            modifier = %{
              "name" => "Big stuff",
              "description" => "Some cool shit is happening"
            }
          %>


          <%= if Enum.any?(waypoint["modifiers"]) do %>
          <div class="card bg-warning text-warning-content max-w-96">
            <div class="card-body">
              <h2 class="card-title">{modifier["name"]}</h2>
              <p>{modifier["description"]}</p>
            </div>
          </div>
          <% end %>
        </div>


        <div role="tablist" class="tabs tabs-lift mb-4 w-full">
          <a role="tab" class={if @waypoint_tab == "info", do: ["tab tab-active"], else: ["tab"]} phx-click="select-waypoint-tab" phx-value-waypoint-tab="info">Info</a>
          <div class="tab-content border-base-300 p-6">
            <div :if={@waypoint_tab == "info"}>

              <div :if={is_binary(waypoint["orbits"])} class="mb-8">
                <div class="text-lg font-bold mb-4">
                  Orbits
                </div>

                <.link class="link" patch={~p"/game/systems/#{waypoint["systemSymbol"]}/waypoints/#{waypoint["orbits"]}"}>{waypoint["orbits"]}</.link>
              </div>

              <div :if={Enum.any?(waypoint["orbitals"])} class="mb-8">
                <div class="text-lg font-bold mb-4">
                  Orbitals
                </div>

                <ul class="list">
                  <li :for={orbital <- waypoint["orbitals"]} class="list-row">
                    <.link class="link" patch={~p"/game/systems/#{waypoint["systemSymbol"]}/waypoints/#{orbital["symbol"]}"}>{orbital["symbol"]}</.link>
                  </li>
                </ul>
              </div>

              <%= if waypoint["isUnderConstruction"] do %>
                <div class="mb-8">
                  <div class="font-bold text-lg mb-4">
                    Construction Site
                  </div>

                  <.async_result :let={construction} assign={@construction_site}>
                    <:loading><span class="loading loading-ring loading-lg"></span></:loading>
                    <:failed :let={_failure}>There was an error loading the construction site.</:failed>

                    <%= if construction["isComplete"] do %>
                      Construction is completed.

                    <% else %>
                      Required resources

                      <table class="table">
                        <%= for material <- construction["materials"] do %>
                          <tr>
                            <td><%= material["tradeSymbol"] %></td>
                            <td><%= material["fulfilled"] %> / <%= material["required"] %></td>
                          </tr>

                        <% end %>
                      </table>
                    <% end %>


                  </.async_result>
                </div>
              <% end %>

              <% contracts_here = deliveries_here(@contracts, @waypoint_symbol) %>
              <%= if Enum.any?(contracts_here) do %>
                <div class="mb-8">

                  <div class="font-bold text-lg mb-4">
                    Contracts
                  </div>

                  <%= for contract <- contracts_here do %>
                    <div class="border-neutral border rounded-lg p-4 w-1/3">
                      <div class="mb-4">
                        <div class="font-bold">
                          <.link
                            class="link-hover"
                            patch={~p"/game/contracts/#{contract["id"]}"}
                          >
                            <%= contract["type"] %>
                            for
                            <%= contract["factionSymbol"] %>
                          </.link>
                        </div>
                        <div class="text-sm opacity-50">
                          Expires at <%= contract["terms"]["deadline"] %>
                        </div>
                      </div>

                      <div :if={@fleet.ok?}>
                        <%= for delivery <- contract["terms"]["deliver"] do %>
                          <%= if delivery["destinationSymbol"] == @waypoint_symbol do %>
                            <% ships = ships_with_cargo(@fleet.result, delivery["tradeSymbol"]) %>
                            <% delivery_fulfilled = delivery["unitsFulfilled"] == delivery["unitsRequired"] %>

                            <details class={["collapse collapse-arrow bg-base-200"]}>

                              <summary class="collapse-title">
                                <div class="flex flex-row justify-between">
                                  <div class="flex flex-row items-center">
                                    <%= if delivery_fulfilled do %>
                                      <.icon name="hero-check-circle" class="w-8" />
                                    <% else %>
                                      <.icon name="hero-minus-circle" class="w-8" />
                                    <% end %>

                                    <div><%= delivery["tradeSymbol"] %></div>

                                    <%= if Enum.any?(ships) do %>
                                      <span class="badge badge-xs badge-primary ml-4"></span>
                                    <% end %>
                                  </div>
                                  <div class="">
                                    <%= delivery["unitsFulfilled"] %> /
                                    <%= delivery["unitsRequired"] %>
                                  </div>
                                </div>
                              </summary>

                              <div class="collapse-content">
                                <%= if Enum.any?(ships) do %>
                                  <%= for ship <- ships do %>
                                    <% deliverable_count = units_deliverable(ship, contract, delivery["tradeSymbol"]) %>
                                    <div class="flex flex-row justify-between ml-9 mb-2">
                                      <span><%= ship["registration"]["name"] %></span>
                                      <button
                                        class="btn btn-xs btn-primary"
                                        phx-click="deliver-contract-cargo"
                                        phx-value-contract-id={contract["id"]}
                                        phx-value-ship-symbol={ship["symbol"]}
                                        phx-value-trade-symbol={delivery["tradeSymbol"]}
                                        phx-value-units={deliverable_count}
                                      >
                                        Deliver
                                        <%= deliverable_count %>
                                      </button>
                                    </div>
                                  <% end %>
                                <% else %>
                                  <p class="opacity-50 italic">No ships availble to fulfill this request</p>
                                <% end %>
                              </div>
                            </details>
                          <% end %>
                        <% end %>
                      </div>
                    </div>
                  <% end %>

                </div>
              <% end %>

              <.async_result :let={fleet} assign={@fleet}>
                <:loading><span class="loading loading-ring loading-lg"></span></:loading>
                <:failed :let={_failure}>There was an error loading the fleet.</:failed>
              <div class="mb-4">
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
                    <%= for ship <- @ships_at_waypoint do %>
                      <tr>
                        <td>
                          <.link
                            class="link-hover"
                            patch={~p"/game/systems/#{ship["nav"]["systemSymbol"]}/waypoints/#{ship["nav"]["waypointSymbol"]}/ships/#{ship["symbol"]}"}
                          >
                          <%= ship["registration"]["name"] %>
                          </.link>
                        </td>
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
                    phx-click="purchase-fuel"
                    phx-value-ship-symbol={ship["symbol"]}
                    disabled={ship["nav"]["status"] != "DOCKED" || ship["fuel"]["capacity"] in [0, nil] || ship["fuel"]["capacity"] == ship["fuel"]["current"]}
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
                    <% end %>systems
                  </tbody>
                </table>

              </div>

              <div>



                <div class="font-bold text-lg mb-4">
                  Ships in this system
                </div>

                <% ships_in_system = Enum.filter(fleet, fn ship -> ship["nav"]["systemSymbol"] == @system_symbol end) %>

                <table class="table table-zebra table-fixed">
                  <thead>
                    <tr>
                      <th>Name</th>
                      <th class="w-32">Location</th>
                      <th class="w-24">Distance</th>
                      <th class="w-32">Role</th>
                      <th class="w-24">Status</th>
                      <th class="w-28">Condition</th>
                      <th class="w-28">Fuel</th>
                      <th>Actions</th>
                    </tr>
                  </thead>

                  <tbody>
                    <%= for ship <- ships_in_system do %>
                      <tr>
                        <td>
                          <.link
                            class="link-hover"
                            patch={~p"/game/fleet/#{ship["symbol"]}"}
                          >
                          <%= ship["registration"]["name"] %>
                          </.link>
                        </td>
                        <td>

                          <.link
                            class="link-hover"
                            patch={~p"/game/systems/#{ship["nav"]["systemSymbol"]}/waypoints/#{ship["nav"]["waypointSymbol"]}"}
                          >
                            <%= ship["nav"]["waypointSymbol"] %>
                          </.link>

                        </td>
                        <td>
                          <.async_result :let={system} assign={@system}>
                            <:loading><span class="loading loading-ring loading-lg"></span></:loading>
                            <:failed :let={_failure}>There was an error loading the system.</:failed>
                            <%= trunc(Float.round(distance(system, @waypoint_symbol, ship["nav"]["waypointSymbol"]))) %>u
                          </.async_result>
                        </td>
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
                          <div class="join">
                            <button
                              class="btn btn-sm btn-accent join-item"
                              phx-click="navigate-ship"
                              phx-value-ship-symbol={ship["symbol"]}
                              phx-value-system-symbol={@system_symbol}
                              phx-value-waypoint-symbol={@waypoint_symbol}
                              phx-value-flight-mode={@selected_flight_mode}
                              disabled={ship["nav"]["status"] != "IN_ORBIT"}
                            >
                              <%= @selected_flight_mode %> here
                            </button>
                            <details class="dropdown">
                              <summary class="btn btn-sm btn-outline btn-accent btn-square rounded-l-none">
                                <Heroicons.chevron_down class="w-4 h-4" />
                              </summary>
                              <ul class="menu dropdown-content bg-base-100 rounded-box z-[1] w-52 p-2 shadow">
                                <li><a phx-click="flight-mode-selected" phx-value-flight-mode="CRUISE">CRUISE</a></li>
                                <li><a phx-click="flight-mode-selected" phx-value-flight-mode="BURN">BURN</a></li>
                                <li><a phx-click="flight-mode-selected" phx-value-flight-mode="DRIFT">DRIFT</a></li>
                                <li><a phx-click="flight-mode-selected" phx-value-flight-mode="STEALTH">STEALTH</a></li>
                              </ul>
                            </details>

                          </div>

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
              </.async_result>
            </div>
          </div>



          <%= if Enum.find(waypoint["traits"], fn trait -> trait["symbol"] == "MARKETPLACE" end) do %>
            <a role="tab" class={if @waypoint_tab == "market", do: ["tab tab-active"], else: ["tab"]} phx-click="select-waypoint-tab" phx-value-waypoint-tab="market">Market</a>

            <div class="tab-content border-base-300">
              <div :if={@waypoint_tab == "market"}>
                <.async_result :let={market} assign={@market}>

                  <%= if market do %>
                    <div class="mb-8">
                      <SpacetradersClientWeb.WaypointMarketComponent.imports_exports
                        market={market}
                        system_symbol={waypoint["systemSymbol"]}
                        waypoint_symbol={waypoint["symbol"]}
                      />
                    </div>
                  <% end %>

                  <div class="flex flex-row justify-center items-center mb-8 p-4 gap-8 bg-base-300 rounded">
                    <div class="text-lg font-bold text-right">
                      Select ship
                    </div>


                    <form phx-change="select-ship">
                      <select class="select select-border w-72" name="ship-symbol">
                        <%= for ship <- @ships_at_waypoint do %>
                          <option value={ship["symbol"]}>
                            <%= ship["registration"]["name"] %>
                          </option>
                        <% end %>
                      </select>
                    </form>

                    <div class="divider divider-horizontal"></div>

                    <form class="w-20" phx-change="set-market-action">
                      <div class="form-control">
                        <label class="label cursor-pointer">
                          <input type="radio" name="radio-market" class="radio" value="buy" checked={@market_action == "buy"} />
                          <span class="label-text">Buy</span>
                        </label>
                      </div>
                      <div class="form-control">
                        <label class="label cursor-pointer">
                          <input type="radio" name="radio-market" class="radio" value="sell" checked={@market_action == "sell"} />
                          <span class="label-text">Sell</span>
                        </label>
                      </div>
                    </form>
                  </div>

                  <%= case @market_action do %>
                    <% "sell" -> %>
                      <div>
                        <%= if anything_to_sell?(@ships_at_waypoint, market) do %>
                          <table class="table table-zebra">
                            <thead>
                              <tr>
                                <th>Ship</th>
                                <th>Item</th>
                                <th class="text-right">Quantity</th>
                                <th class="text-right">Value</th>
                                <th></th>
                              </tr>
                            </thead>
                            <tbody>
                              <%= for ship <- @ships_at_waypoint do %>
                                <%= for item <- ship["cargo"]["inventory"] do %>
                                  <% sell_value = cargo_sell_value(market, item) %>
                                  <%= if is_integer(sell_value) do %>
                                    <tr>
                                      <td><%= ship["registration"]["name"] %></td>
                                      <td><%= item["name"] %></td>
                                      <td class="text-right"><%= item["units"] %></td>
                                      <td class="text-right"><%= sell_value %></td>
                                      <td class="text-right">
                                        <button
                                          class="btn btn-xs btn-success"
                                          phx-click="sell-cargo"
                                          phx-value-ship-symbol={ship["symbol"]}
                                          phx-value-trade-symbol={item["symbol"]}
                                          phx-value-units={item["units"]}
                                        >
                                          Sell
                                        </button>
                                      </td>
                                    </tr>
                                  <% end %>
                                <% end %>
                              <% end %>
                            </tbody>
                          </table>
                        <% else %>
                          <div class="opacity-50 italic text-center mt-32">
                            This ship has no items that the market is buying
                          </div>
                        <% end %>
                      </div>

                    <% "buy" -> %>

                      <div>
                        <%= if market do %>
                          <%= if items = market["tradeGoods"] do %>
                            <SpacetradersClientWeb.WaypointMarketComponent.item_table items={items} />
                          <% end %>
                        <% end %>
                      </div>
                  <% end %>
              </.async_result>
              </div>
            </div>




          <% end %>
          <%= if waypoint["type"] in ~w(ASTEROID ASTEROID_FIELD ENGINEERED_ASTEROID) do %>
            <a role="tab" class={if @waypoint_tab == "mining", do: ["tab tab-active"], else: ["tab"]} phx-click="select-waypoint-tab" phx-value-waypoint-tab="mining">Mining</a>

            <div class="tab-content bg-base-300">
              <div :if={@waypoint_tab == "mining"}>

                <div>
                  <% selected_ship = Enum.find(@ships_at_waypoint, fn s -> s["symbol"] == @selected_ship_symbol end) %>

                  <div class="flex flex-row justify-center items-center mb-8 p-4 gap-8 bg-base-300 rounded">
                    <%= if Enum.any?(@ships_at_waypoint) do %>
                      <div class="text-lg font-bold text-right">
                        Select ship
                      </div>

                      <form phx-change="select-ship">
                        <select class="select select-border w-72" name="ship-symbol">
                          <%= for ship <- @ships_at_waypoint do %>
                            <option value={ship["symbol"]} selected={@selected_ship_symbol == ship["symbol"]}>
                              <%= ship["registration"]["name"] %>
                            </option>
                          <% end %>
                        </select>
                      </form>

                      <.link
                        class="btn btn-neutral"
                        patch={"/game/systems/#{@system_symbol}/waypoints/#{@waypoint_symbol}/ships/#{@selected_ship_symbol}"}
                      >
                        View ship
                      </.link>

                      <div class="w-64 h-32">
                        <%= if @selected_ship_symbol do %>
                          <SpacetradersClientWeb.ShipStatsComponent.cargo ship={Enum.find(@ships_at_waypoint, fn s -> s["symbol"] == @selected_ship_symbol end)} />
                        <% end %>
                      </div>
                    <% else %>
                      <div class="text-lg font-bold text-right">
                        No ships at waypoint
                      </div>
                    <% end %>

                  </div>

                  <div class="flex flex-col justify-center items-center mb-8">
                    <%= cond do %>
                      <% Enum.empty?(@ships_at_waypoint) -> %>
                        There are no ships capable of mining at this waypoint
                      <% selected_ship["nav"]["status"] == "IN_TRANSIT" -> %>
                        <div class="mb-4">
                          Ship is in transit to this location.
                          <span class="countdown font-mono text-lg">
                            <span style={"--value:#{@cooldown_remaining};"}></span>
                          </span>
                          seconds until it arrives.
                        </div>

                        <button
                          class="btn btn-accent btn-outline"
                          phx-click="dock-ship"
                          phx-value-ship-symbol={selected_ship["symbol"]}
                          disabled
                        >
                          Dock
                        </button>
                      <% selected_ship["nav"]["status"] == "DOCKED" -> %>
                        <div class="mb-4">
                          Ship must be in orbit to mine.
                        </div>

                        <button
                          class="btn btn-accent"
                          phx-click="orbit-ship"
                          phx-value-ship-symbol={selected_ship["symbol"]}
                        >
                          Undock
                        </button>

                      <% @cooldown_remaining == 0 -> %>
                        <div class="mb-4">
                          Equipment is ready to use.
                        </div>

                        <button
                          class="btn btn-accent btn-outline"
                          phx-click="dock-ship"
                          phx-value-ship-symbol={selected_ship["symbol"]}
                        >
                          Dock
                        </button>
                      <% true -> %>
                        <div class="mb-4">
                          Equipment is cooling down:
                          <span class="countdown font-mono text-lg">
                            <span style={"--value:#{@cooldown_remaining};"}></span>
                          </span>
                          seconds until functionality returns.
                        </div>

                        <button
                          class="btn btn-accent btn-outline"
                          phx-click="dock-ship"
                          phx-value-ship-symbol={selected_ship["symbol"]}
                          disabled
                        >
                          Dock
                        </button>
                      <% end %>
                  </div>


                  <%= if can_survey?(selected_ship) do %>
                    <div class="flex flex-col items-center">
                      <button
                        phx-click="create-survey"
                        phx-value-ship-symbol={selected_ship["symbol"]}
                        class="btn btn-neutral w-1/2"
                        disabled={selected_ship["nav"]["status"] != "IN_ORBIT" || @cooldown_remaining > 0}
                      >
                        Start survey
                      </button>
                    </div>
                  <% end %>

                  <%= if can_mine?(selected_ship) do %>
                    <div class="flex flex-col items-center">
                      <button
                        phx-click="extract-resources"
                        phx-value-ship-symbol={selected_ship["symbol"]}
                        class="btn btn-primary w-1/2"
                        disabled={selected_ship["nav"]["status"] != "IN_ORBIT" || @cooldown_remaining > 0}
                      >
                        Start mining
                      </button>
                    </div>
                  <%end %>

                  <div>
                    <table class="table">
                      <thead>
                        <tr>
                          <th class="w-12">Use</th>
                          <th class="w-64">Survey ID</th>
                          <th>Deposits</th>
                        </tr>
                      </thead>
                      <tbody>
                        <%= for survey <- @surveys do %>
                          <%
                            [{first_freq_symbol, first_freq_count} | rest_freqs] =
                              Enum.frequencies_by(survey["deposits"], fn d -> d["symbol"] end)
                              |> Enum.to_list()
                              |> Enum.sort_by(fn {_, count} -> count end, :desc)

                            unique_symbol_count =
                              Enum.map(survey["deposits"], fn d -> d["symbol"] end)
                              |> Enum.uniq()
                              |> Enum.count()

                          %>
                          <tr>
                            <td rowspan={unique_symbol_count}>
                              <input
                                class="radio"
                                type="radio"
                                name="survey-id"
                                value={survey["signature"]}
                                checked={@selected_survey_id == survey["signature"]}
                                phx-click="survey-selected"
                              />
                            </td>
                            <td rowspan={unique_symbol_count}><%= survey["signature"] %></td>
                            <td>
                              <%= first_freq_symbol %> &times;<%= first_freq_count %>
                            </td>
                          </tr>
                          <%= for {symbol, count} <- rest_freqs do %>
                            <tr>
                              <td>
                                <%= symbol %> &times;<%= count %>
                              </td>
                            </tr>
                          <% end %>
                        <% end %>
                      </tbody>
                    </table>
                  </div>
                </div>
              </div>
            </div>

          <% end %>

          <%= if Enum.find(waypoint["traits"], fn trait -> trait["symbol"] == "SHIPYARD" end) do %>
            <a role="tab" class={if @waypoint_tab == "shipyard", do: ["tab tab-active"], else: ["tab"]} phx-click="select-waypoint-tab" phx-value-waypoint-tab="shipyard">Shipyard</a>

            <div class="tab-content border-base-300">
              <div :if={@waypoint_tab == "shipyard"}>

                <div>
                  <.async_result :let={shipyard} assign={@shipyard}>
                    <%= if Enum.any?(@ships_at_waypoint) && shipyard do %>
                      <table class="table table-zebra">
                        <tbody>
                          <%= for ship <- shipyard["ships"] do %>
                            <tr>
                              <td><%= ship["name"] %></td>
                              <td>
                                <p class="mb-2"><%= ship["description"] %></p>
                                <div class="flex flex-row justify-between">
                                  <div>
                                    <div class="font-bold">Frame</div>
                                    <div>
                                      <%= ship["frame"]["name"] %>
                                    </div>
                                    <div>
                                      Module slots: <%= ship["frame"]["moduleSlots"] %>
                                    </div>
                                    <div>
                                      Mounting points: <%= ship["frame"]["mountingPoints"] %>
                                    </div>
                                    <div>
                                      Fuel capacity: <%= ship["frame"]["fuelCapacity"] %>
                                    </div>

                                  </div>

                                  <div>
                                    <div class="font-bold">Engine</div>
                                    <div>
                                      <%= ship["engine"]["name"] %>
                                    </div>
                                    <div>
                                      Speed: <%= ship["engine"]["speed"] %>
                                    </div>
                                  </div>

                                  <div>
                                    <div class="font-bold">Reactor</div>
                                    <div>
                                      <%= ship["reactor"]["name"] %>
                                    </div>
                                    <div>
                                      Speed: <%= ship["reactor"]["powerOutput"] %>
                                    </div>
                                  </div>

                                  <div>
                                    <div class="font-bold">Modules</div>
                                    <ul class="list-disc">
                                    <%= for module <- ship["modules"] do %>
                                      <li class="ml-3">
                                        <%= module["name"] %>
                                        <%= if module["capacity"] do %>
                                          (capacity: <%= module["capacity"] %>)
                                        <% end %>
                                      </li>
                                    <% end %>
                                    </ul>
                                  </div>

                                  <div>
                                    <div class="font-bold">Mounts</div>
                                    <ul class="list-disc">
                                    <%= for module <- ship["mounts"] do %>
                                      <li class="ml-3"><%= module["name"] %></li>
                                    <% end %>
                                    </ul>
                                  </div>

                                </div>

                              </td>
                              <td><%= ship["supply"] %></td>
                              <td><%= ship["purchasePrice"] %></td>
                              <td>
                                <button
                                  class="btn btn-error"
                                  phx-click="purchase-ship"
                                  phx-value-ship-type={ship["type"]}
                                  phx-value-waypoint-symbol={@waypoint_symbol}
                                >
                                  Buy
                                </button>
                              </td>

                            </tr>
                          <% end %>
                        </tbody>
                      </table>
                    <% else %>
                      A ship must be present at this waypoint to use the shipyard.
                    <% end %>
                  </.async_result>
                </div>
              </div>
            </div>


          <% end %>

          <a role="tab" class={if @waypoint_tab == "chart", do: ["tab tab-active"], else: ["tab"]} phx-click="select-waypoint-tab" phx-value-waypoint-tab="chart">Chart</a>

          <div class="tab-content border-base-300">
            <div :if={@waypoint_tab == "chart"}>
              Chart go here
            </div>
          </div>
        </div>

      </.async_result>
    </div>
    """
  end

  def mount(_params, %{"token" => token}, socket) do
    client = Client.new(token)
    {:ok, %{status: 200, body: agent_body}} = Agents.my_agent(client)
    PubSub.subscribe(@pubsub, "agent:#{agent_body["data"]["symbol"]}")
    callsign = agent_body["data"]["symbol"]

    socket =
      assign(socket, %{
        app_section: :galaxy,
        client: client,
        agent: AsyncResult.ok(agent_body["data"]),
        waypoint_tab: "info",
        market_action: "buy",
        cooldown_remaining: 0,
        selected_survey_id: nil,
        selected_flight_mode: "CRUISE",
        contracts: []
      })
      |> assign_async(:agent_automaton, fn ->
        case AutomationServer.automaton(callsign) do
          {:ok, a} -> {:ok, %{agent_automaton: a}}
          {:error, _} -> {:ok, %{agent_automaton: nil}}
        end
      end)
      |> load_fleet()

    {:ok, socket}
  end

  def handle_params(params, _uri, socket) do
    socket =
      assign(socket, %{
        waypoint_symbol: params["waypoint_symbol"],
        system_symbol: params["system_symbol"]
      })

    client = socket.assigns.client
    waypoint_symbol = socket.assigns.waypoint_symbol
    system_symbol = socket.assigns.system_symbol

    socket =
      socket
      |> assign_async(:market, fn ->
        case Systems.get_market(client, system_symbol, waypoint_symbol) do
          {:ok, %{status: 200, body: body}} ->
            body["data"]

          {:ok, %{status: 404}} ->
            nil
        end
      end)
      |> assign(:shipyard, AsyncResult.loading())
      |> assign(:construction_site, AsyncResult.loading())
      |> assign_async(:system, fn ->
        case Systems.get_system(client, system_symbol) do
          {:ok, s} -> {:ok, %{system: s.body["data"]}}
          {:error, reason} -> {:error, reason}
        end
      end)
      |> assign_async(:waypoint, fn ->
        case Systems.get_waypoint(client, system_symbol, waypoint_symbol) do
          {:ok, w} ->
            {:ok, %{waypoint: w.body["data"]}}

          {:error, reason} ->
            {:error, reason}
        end
      end)

    {:noreply, socket}
  end

  def handle_event("select-waypoint-tab", %{"waypoint-tab" => waypoint_tab}, socket) do
    {:noreply, assign(socket, :waypoint_tab, waypoint_tab)}
  end

  def handle_event("set-market-action", %{"radio-market" => action}, socket)
      when action in ~w(buy sell) do
    {:noreply, assign(socket, :market_action, action)}
  end

  def handle_event("flight-mode-selected", %{"flight-mode" => mode}, socket)
      when mode in ~w(CRUISE BURN DRIFT STEALTH) do
    {:noreply, assign(socket, :selected_flight_mode, mode)}
  end

  def handle_async(:get_waypoint, {:ok, {:ok, %{status: 200, body: body}}}, socket) do
    client = socket.assigns.client
    system_symbol = socket.assigns.system_symbol
    waypoint_symbol = socket.assigns.waypoint_symbol

    socket =
      if Enum.any?(body["data"]["traits"], fn t -> t["symbol"] == "MARKETPLACE" end) do
        assign_async(socket, :market, fn ->
          case Systems.get_market(client, system_symbol, waypoint_symbol) do
            {:ok, %{status: 200, body: body}} ->
              {:ok, %{market: body["data"]}}

            {:ok, %{status: 404}} ->
              {:ok, %{market: nil}}
          end
        end)
      else
        socket
        |> assign(:market, AsyncResult.ok(nil))
        |> then(fn socket ->
          if socket.assigns[:waypoint_tab] == "market" do
            assign(socket, :waypoint_tab, "info")
          else
            socket
          end
        end)
      end

    socket =
      if Enum.any?(body["data"]["traits"], fn t -> t["symbol"] == "SHIPYARD" end) do
        assign_async(socket, :shipyard, fn ->
          case Systems.get_shipyard(client, system_symbol, waypoint_symbol) do
            {:ok, %{status: 200, body: body}} ->
              {:ok, %{shipyard: body["data"]}}
          end
        end)
      else
        socket
        |> assign(:shipyard, AsyncResult.ok(nil))
        |> then(fn socket ->
          if socket.assigns[:waypoint_tab] == "shipyard" do
            assign(socket, :waypoint_tab, "info")
          else
            socket
          end
        end)
      end

    socket =
      if body["data"]["isUnderConstruction"] do
        assign_async(socket, :construction_site, fn ->
          case Systems.get_construction_site(client, system_symbol, waypoint_symbol) do
            {:ok, %{status: 200, body: body}} ->
              {:ok, %{construction_site: body["data"]}}

            {:ok, %{status: 404}} ->
              {:ok, %{construction_site: nil}}
          end
        end)
      else
        assign(socket, :construction_site, AsyncResult.ok(nil))
      end

    {:noreply, assign(socket, :waypoint, AsyncResult.ok(body["data"]))}
  end

  def handle_async(:update_counter, _, socket) do
    socket =
      assign(
        socket,
        :cooldown_remaining,
        seconds_til_cooldown_expiration(
          Enum.find(socket.assigns.fleet, fn s ->
            s["symbol"] == socket.assigns.selected_ship_symbol
          end)
        )
      )

    socket = schedule_cooldown_update(socket)

    {:noreply, socket}
  end

  def handle_async(:load_fleet, {:ok, result}, socket) do
    page = Map.fetch!(result.meta, "page")

    socket =
      if page == 1 do
        assign(socket, :fleet, AsyncResult.loading(result.data))
      else
        assign(
          socket,
          :fleet,
          AsyncResult.loading(socket.assigns.fleet, socket.assigns.fleet.loading ++ result.data)
        )
      end

    socket =
      if Enum.count(socket.assigns.fleet.loading) < Map.fetch!(result.meta, "total") do
        load_fleet(socket, page + 1)
      else
        assign(socket, :fleet, AsyncResult.ok(socket.assigns.fleet, socket.assigns.fleet.loading))
      end

    {:noreply, socket}
  end

  defp load_fleet(socket, page \\ 1) do
    client = socket.assigns.client

    start_async(socket, :load_fleet, fn ->
      case Fleet.list_ships(client, page: page) do
        {:ok, %{status: 200, body: body}} ->
          %{
            meta: body["meta"],
            data: body["data"]
          }

        {:ok, resp} ->
          {:error, resp}

        err ->
          err
      end
    end)
  end

  defp anything_to_sell?(fleet, market) do
    Enum.any?(fleet, fn ship ->
      Enum.any?(ship["cargo"]["inventory"], fn inventory_item ->
        cargo_sell_value(market, inventory_item)
        |> is_integer()
      end)
    end)
  end

  defp cargo_sell_value(market, inventory_item) do
    if market do
      trade_good =
        Enum.find(market["tradeGoods"], fn trade_good ->
          trade_good["symbol"] == inventory_item["symbol"]
        end)

      if is_map(trade_good) do
        trade_good["sellPrice"] * inventory_item["units"]
      end
    end
  end

  defp condition_percentage(ship) do
    (ship["frame"]["condition"] +
       ship["reactor"]["condition"] +
       ship["engine"]["condition"])
    |> then(fn sum ->
      sum / 3 * 100
    end)
    |> Float.round(0)
    |> trunc()
  end

  defp deliveries_here(contracts, waypoint_symbol) do
    Enum.filter(contracts, fn contract ->
      not contract["fulfilled"] &&
        Enum.any?(contract["terms"]["deliver"], fn delivery ->
          delivery["destinationSymbol"] == waypoint_symbol
        end)
    end)
  end

  defp ships_with_deliverables(fleet, contracts) do
    Enum.filter(fleet, fn ship ->
      Enum.any?(contracts, fn contract ->
        deliverables(ship, contract)
      end)
    end)
  end

  defp deliverables(ship, contract) do
    Enum.map(contract["terms"]["deliver"], fn deliverable ->
      cargo_item(ship, deliverable["tradeSymbol"])
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp ships_with_cargo(fleet, item_symbol) do
    Enum.filter(fleet, fn ship ->
      cargo_item(ship, item_symbol)
    end)
  end

  defp cargo_item(ship, item_symbol) do
    Enum.find(ship["cargo"]["inventory"], fn ship_item ->
      ship_item["symbol"] == item_symbol
    end)
  end

  defp units_deliverable(ship, contract, item_symbol) do
    item_to_deliver =
      Enum.find(contract["terms"]["deliver"], fn deliverable ->
        deliverable["tradeSymbol"] == item_symbol
      end)

    item_in_cargo =
      Enum.find(ship["cargo"]["inventory"], fn item ->
        item["symbol"] == item_symbol
      end)

    if item_to_deliver && item_in_cargo do
      min(item_to_deliver["units"], item_in_cargo["units"])
    else
      0
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

  defp schedule_cooldown_update(socket) do
    if socket.assigns[:cooldown_remaining] && socket.assigns.cooldown_remaining > 0 do
      start_async(socket, :update_counter, fn ->
        Process.sleep(250)
        :ok
      end)
    else
      socket
    end
  end

  defp can_survey?(nil), do: false

  defp can_survey?(ship) do
    Enum.any?(ship["mounts"], fn mount ->
      mount["symbol"] in ~w(MOUNT_SURVEYOR_I MOUNT_SURVEYOR_II MOUNT_SURVEYOR_III)
    end)
  end

  defp can_mine?(nil), do: false

  defp can_mine?(ship) do
    Enum.any?(ship["mounts"], fn mount ->
      mount["symbol"] in ~w(MOUNT_MINING_LASER_I MOUNT_MINING_LASER_II MOUNT_MINING_LASER_III)
    end)
  end

  defp distance(system, wp_a_symbol, wp_b_symbol) do
    wp_a = Enum.find(system["waypoints"], fn w -> w["symbol"] == wp_a_symbol end)
    wp_b = Enum.find(system["waypoints"], fn w -> w["symbol"] == wp_b_symbol end)

    :math.sqrt(:math.pow(wp_a["x"] - wp_b["x"], 2) + :math.pow(wp_a["y"] - wp_b["y"], 2))
  end
end
