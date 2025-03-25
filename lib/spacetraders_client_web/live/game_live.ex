defmodule SpacetradersClientWeb.GameLive do
  use SpacetradersClientWeb, :live_view

  alias SpacetradersClient.Cldr.Number
  alias SpacetradersClient.LedgerServer
  alias Phoenix.LiveView.Socket
  alias Phoenix.LiveView.AsyncResult
  alias SpacetradersClient.Fleet
  alias SpacetradersClient.Agents
  alias SpacetradersClient.Client
  alias SpacetradersClient.Systems
  alias SpacetradersClient.Contracts
  alias SpacetradersClient.Fleet

  alias Phoenix.PubSub

  require Logger

  @pubsub SpacetradersClient.PubSub

  attr :system_symbol, :string, default: nil
  attr :waypoint_symbol, :string, default: nil

  def render(assigns), do: render_new(assigns)

  def render_new(assigns) do
    ~H"""
      <.live_component
        module={SpacetradersClientWeb.OrbitalsMenuComponent}
        id="orbitals"
        client={@client}
        system_symbol={@system_symbol}
        waypoint_symbol={@waypoint_symbol}
        fleet={@fleet}
      >
        <%= case @live_action do %>
          <% :agent -> %>
            <.async_result :let={agent} assign={@agent}>
              <:loading><span class="loading loading-ring loading-lg"></span></:loading>
              <:failed :let={_failure}>There was an error loading your agent.</:failed>

              <.live_component
                module={SpacetradersClientWeb.AgentComponent}
                id="my-agent"
                client={@client}
                ledger={@ledger}
                agent={agent}
              />
            </.async_result>
          <% :fleet -> %>
            <.async_result :let={fleet} assign={@fleet}>
              <:loading><span class="loading loading-ring loading-lg"></span></:loading>
              <:failed :let={_failure}>There was an error loading your fleet</:failed>

              <.async_result :let={agent_automaton} assign={@agent_automaton}>
                <:loading><span class="loading loading-ring loading-lg"></span></:loading>
                <:failed :let={_failure}>There was an error loading fleet automata</:failed>

                <.live_component
                  module={SpacetradersClientWeb.FleetComponent}
                  id="fleet-screen"
                  fleet={fleet},
                  fleet_automata={if agent_automaton, do: agent_automaton.ship_automata}
                />
              </.async_result>
            </.async_result>
          <% :waypoint -> %>
            <.live_component
              id={@waypoint_symbol}
              module={SpacetradersClientWeb.WaypointComponent}
              client={@client}
              waypoint={@waypoint} waypoint_symbol={@waypoint_symbol} system={@system} system_symbol={@system_symbol} waypoint_tab={@waypoint_tab} fleet={@fleet} selected_flight_mode={@selected_flight_mode} />
        <% end %>
      </.live_component>
    """
  end

  def render_old(assigns) do
    ~H"""
    <.async_result :let={agent} assign={@agent}>
      <:loading><span class="loading loading-ring loading-lg"></span></:loading>
      <:failed :let={_failure}>Failed to fetch your agent</:failed>
      <div
        class="flex flex-row min-h-screen max-h-screen h-screen"
        phx-hook="SurveyStorage"
        id="gamedata"
      >
        <div class="bg-base-300 w-1/6 flex-none overflow-y-auto">
          <.link class="hover:link" patch={~p"/game/agent"}>
            <div class="px-5 py-2 bg-neutral w-full flex justify-between items-center">
              <span>
                <.icon name="hero-user" />
                <span class="font-mono"><%= agent["symbol"] %></span>
              </span>
              <span class="badge">
                <.icon name="hero-circle-stack" class="w-4 h-4" />
                <%= Number.to_string!(agent["credits"], format: :accounting, fractional_digits: 0) %>
              </span>
            </div>
          </.link>

          <ul class="menu menu bg-base-300 w-full">
            <li>
              <details>
                <summary class="">
                  <.icon name="hero-book-open" />
                  <span>Contracts</span>
                </summary>
                <.async_result :let={contracts} assign={@contracts}>
                  <:loading><span class="loading loading-ring loading-lg"></span></:loading>
                  <:failed :let={_failure}>There was an error your contracts.</:failed>

                  <ul>
                    <%= for contract <- contracts do %>
                      <li>
                        <.link patch={~p"/game/contracts/#{contract["id"]}"}>
                          <%= contract["type"] %>
                        </.link>
                      </li>
                    <% end %>
                  </ul>
                </.async_result>
              </details>
            </li>

            <li>
              <details open={is_binary(@selected_ship_symbol)}>
                <summary class="">
                  <.icon name="hero-rocket-launch" />
                  <span>Fleet</span>
                  <span>
                    <.async_result :let={agent} assign={@agent}>
                      <:loading><span class="loading loading-ring loading-lg"></span></:loading>
                      <:failed :let={_failure}>ERR</:failed>

                      <%= agent["shipCount"] %>
                    </.async_result>
                  </span>
                </summary>
                <ul>
                  <.async_result :let={fleet} assign={@fleet}>
                    <:loading><span class="loading loading-ring loading-lg"></span></:loading>
                    <:failed :let={_failure}>There was an error fetching your fleet</:failed>

                    <%= for ship <- fleet do %>
                      <li>
                        <.link
                          class={[
                            @selected_ship_symbol == ship["symbol"] && "active",
                            "flex flex-row justify-between items-center"
                          ]}
                          patch={
                            ~p"/game/systems/#{ship["nav"]["systemSymbol"]}/waypoints/#{ship["nav"]["waypointSymbol"]}/ships/#{ship["symbol"]}"
                          }
                        >
                          <span>
                            <%= ship["registration"]["name"] %>
                          </span>
                          <span class="ml-4 text-sm opacity-50"><%= ship["registration"]["role"] %></span>
                          <span class="w-4">
                            <.async_result :let={automaton} assign={@agent_automaton}>
                              <%= if automaton && automaton.ship_automata[ship["symbol"]] do %>
                                <span
                                  class="tooltip tooltip-left tooltip-info"
                                  data-tip="This ship is currently controlled by automation"
                                >
                                  <.icon name="hero-cog" />
                                </span>
                              <% end %>
                            </.async_result>
                          </span>
                        </.link>
                      </li>
                    <% end %>
                  </.async_result>
                </ul>
              </details>
            </li>
            <li>
              <details>
                <summary class="">
                  <.icon name="hero-globe-alt" />
                  <span>Systems</span>
                </summary>
                <ul>
                  <.async_result :let={fleet} assign={@fleet}>
                    <:loading><span class="loading loading-ring loading-lg"></span></:loading>
                    <:failed :let={_failure}>There was an error loading your fleet</:failed>

                    <%= for {system_symbol, ship_count} <- Enum.frequencies(Enum.map(fleet, fn ship -> ship["nav"]["systemSymbol"] end)) do %>
                      <li>
                        <.link patch={~p"/game/systems/#{system_symbol}"}>
                          <span></span>
                          <span><%= system_symbol %></span>
                          <span><%= ship_count %></span>
                        </.link>
                      </li>
                    <% end %>
                  </.async_result>
                </ul>
              </details>
            </li>
          </ul>
        </div>

        <%= case @live_action do %>
          <% :agent -> %>
            <.async_result :let={agent} assign={@agent}>
              <:loading><span class="loading loading-ring loading-lg"></span></:loading>
              <:failed :let={_failure}>There was an error loading your agent.</:failed>

              <.live_component
                module={SpacetradersClientWeb.AgentComponent}
                id="my-agent"
                client={@client}
                ledger={@ledger}
                agent={agent}
              />
            </.async_result>
          <% :contract -> %>
            <div class="min-h-screen max-h-screen w-full">
              <h3 class="px-5 py-2 bg-neutral">
                <a class="font-bold text-xl">
                  Contract
                </a>
              </h3>

              <div class="p-8">
                <.async_result :let={contract} assign={@contract}>
                  <:loading><span class="loading loading-ring loading-lg"></span></:loading>
                  <:failed :let={_failure}>There was an error loading the contract.</:failed>

                  <SpacetradersClientWeb.ContractComponent.view contract={contract} />
                </.async_result>
              </div>
            </div>

          <% :fleet -> %>

            <.async_result :let={fleet} assign={@fleet}>
              <:loading><span class="loading loading-ring loading-lg"></span></:loading>
              <:failed :let={_failure}>There was an error loading your fleet</:failed>

              <.async_result :let={agent_automaton} assign={@agent_automaton}>
                <:loading><span class="loading loading-ring loading-lg"></span></:loading>
                <:failed :let={_failure}>There was an error loading fleet automata</:failed>

                <.live_component
                  module={SpacetradersClientWeb.FleetComponent}
                  id="fleet-screen"
                  fleet={fleet},
                  fleet_automata={if agent_automaton, do: agent_automaton.ship_automata}
                />
              </.async_result>
            </.async_result>


          <% :system -> %>
            <.async_result :let={system} assign={@system}>
              <:loading><span class="loading loading-ring loading-lg"></span></:loading>
              <:failed :let={_failure}>There was an error loading the system.</:failed>

              <.async_result :let={fleet} assign={@fleet}>
                <:loading><span class="loading loading-ring loading-lg"></span></:loading>
                <:failed :let={_failure}>There was an error loading your fleet.</:failed>

                <section class="flex flex-row min-h-screen max-h-screen w-1/6 flex-none">
                  <div class="h-screen bg-base-200">
                    <div class="w-80 max-h-full h-full flex flex-col">
                      <h3 class="px-5 py-2 bg-neutral">
                        <.link
                          class="font-bold text-xl hover:link"
                          patch={~p"/game/systems/#{@system_symbol}"}
                        >
                          <%= @system_symbol %>
                        </.link>
                      </h3>

                      <div class="overflow-auto">
                        <.live_component
                          module={SpacetradersClientWeb.OrbitalsMenuComponent}
                          id="orbitals"
                          system={system}
                          waypoints={@waypoints}
                          fleet={fleet}
                          active_waypoint={@selected_waypoint_symbol}
                        />
                      </div>
                    </div>
                  </div>
                </section>

                <div class="grow">
                  <.live_component
                    module={SpacetradersClientWeb.MapComponent}
                    id="map"
                    client={@client}
                    system={system}
                    fleet={fleet}
                  />
                </div>
              </.async_result>
            </.async_result>
          <% :waypoint -> %>
            <section class="flex flex-row min-h-screen max-h-screen w-1/6 flex-none">
              <div class="h-screen bg-base-200">
                <div class="w-80 max-h-full h-full flex flex-col">
                  <h3 class="px-5 py-2 bg-neutral">
                    <.link
                      class="font-bold text-xl link-hover"
                      patch={~p"/game/systems/#{@system_symbol}"}
                    >
                      <%= @system_symbol %>
                    </.link>
                  </h3>

                  <.async_result :let={system} assign={@system}>
                    <:loading><span class="loading loading-ring loading-lg"></span></:loading>
                    <:failed :let={_failure}>There was an error loading the system.</:failed>

                    <.async_result :let={fleet} assign={@fleet}>
                      <:loading><span class="loading loading-ring loading-lg"></span></:loading>

    Ship 	Role 	System 	Waypoint 	Current task 	Task runtime
                      <:failed :let={_failure}>There was an error loading your fleet.</:failed>

                      <div class="overflow-auto">
                        <.live_component
                          module={SpacetradersClientWeb.OrbitalsMenuComponent}
                          id="orbitals"
                          system={system}
                          waypoints={@waypoints}
                          fleet={fleet}
                          active_waypoint={@selected_waypoint_symbol}
                        />
                      </div>
                    </.async_result>
                  </.async_result>
                </div>
              </div>
            </section>

            <div class="grow h-screen flex flex-col">
              <div class="px-5 py-2 bg-neutral font-bold text-xl">
                <ul>
                  <li>
                    <.link patch={~p"/game/systems/#{@system_symbol}/waypoints/#{@waypoint_symbol}"}>
                      <%= @waypoint_symbol %>
                    </.link>
                  </li>
                </ul>
              </div>

              <div class="overflow-y-auto">
                <.async_result :let={agent} assign={@agent}>
                  <:loading><span class="loading loading-ring loading-lg"></span></:loading>
                  <:failed :let={_failure}>There was an error loading your agent.</:failed>

                  <.async_result :let={fleet} assign={@fleet}>
                    <:loading><span class="loading loading-ring loading-lg"></span></:loading>
                    <:failed :let={_failure}>There was an error loading your fleet.</:failed>

                    <.async_result :let={contracts} assign={@contracts}>
                      <:loading><span class="loading loading-ring loading-lg"></span></:loading>
                      <:failed :let={_failure}>There was an error loading your contracts.</:failed>

                      <.async_result :let={system} assign={@system}>
                        <:loading><span class="loading loading-ring loading-lg"></span></:loading>
                        <:failed :let={_failure}>There was an error loading the system.</:failed>

                        <.live_component
                          module={SpacetradersClientWeb.WaypointComponent}
                          id="waypoint"
                          client={@client}
                          agent={agent}
                          fleet={fleet}
                          system={system}
                          selected_ship_symbol={@selected_ship_symbol}
                          surveys={@surveys}
                          contracts={contracts}
                          system_symbol={@system_symbol}
                          waypoint_symbol={@waypoint_symbol}
                          selected_survey_id={@selected_survey_id}
                        />
                      </.async_result>
                    </.async_result>
                  </.async_result>
                </.async_result>
              </div>
            </div>
          <% :ship -> %>
            <.async_result :let={fleet} assign={@fleet}>
              <:loading><span class="loading loading-ring loading-lg"></span></:loading>
              <:failed :let={_failure}>There was an error loading your fleet.</:failed>

              <.async_result :let={system} assign={@system}>
                <:loading><span class="loading loading-ring loading-lg"></span></:loading>
                <:failed :let={_failure}>There was an error loading the system.</:failed>

                <section class="flex flex-row min-h-screen max-h-screen w-1/6 flex-none overflow-hidden">
                  <div class="h-screen bg-base-200">
                    <div class="w-80 max-h-full h-full flex flex-col">
                      <h3 class="px-5 py-2 bg-neutral">
                        <.link
                          class="font-bold text-xl link-hover"
                          patch={~p"/game/systems/#{@system_symbol}"}
                        >
                          <%= @system_symbol %>
                        </.link>
                      </h3>

                      <div class="overflow-auto">
                        <.live_component
                          module={SpacetradersClientWeb.OrbitalsMenuComponent}
                          id="orbitals"
                          system={system}
                          waypoints={@waypoints}
                          fleet={fleet}
                          active_waypoint={@selected_waypoint_symbol}
                        />
                      </div>
                    </div>
                  </div>
                </section>

                <div class="grow h-screen max-h-screen flex flex-col">
                  <div class="breadcrumbs px-5 py-2 bg-neutral font-bold text-xl flex-none">
                    <ul>
                      <li>
                        <.link patch={
                          ~p"/game/systems/#{@system_symbol}/waypoints/#{@waypoint_symbol}"
                        }>
                          <%= @waypoint_symbol %>
                        </.link>
                      </li>
                      <li>
                        <.link patch={
                          ~p"/game/systems/#{@system_symbol}/waypoints/#{@waypoint_symbol}/ships/#{@selected_ship_symbol}"
                        }>
                          <%= @selected_ship_symbol %>
                        </.link>
                      </li>
                    </ul>
                  </div>

                  <.async_result :let={agent_automaton} assign={@agent_automaton}>
                    <:loading><span class="loading loading-ring loading-lg"></span></:loading>
                    <:failed :let={_failure}>There was an error loading automation.</:failed>

                    <div class="overflow-y-auto">
                      <.live_component
                        module={SpacetradersClientWeb.ShipComponent}
                        id={"ship-#{@selected_ship_symbol}"}
                        client={@client}
                        automaton={
                          if agent_automaton,
                            do: agent_automaton.ship_automata[@selected_ship_symbol],
                            else: nil
                        }
                        agent={agent}
                        system={system}
                        ship={Enum.find(fleet, &(&1["symbol"] == @selected_ship_symbol))}
                      />systems/X1-ZF88/waypoints/X1-ZF88-A1/ships/C0SM1C_R05E-1
                    </div>
                  </.async_result>
                </div>
              </.async_result>
            </.async_result>
        <% end %>
      </div>
    </.async_result>
    """
  end

  def mount(params, %{"token" => token}, socket) do
    client = Client.new(token)

    {:ok, %{status: 200, body: agent_body}} = Agents.my_agent(client)

    PubSub.subscribe(@pubsub, "agent:#{agent_body["data"]["symbol"]}")

    system_symbol = params["system_symbol"]

    app_section =
      case socket.assigns.live_action do
        :waypoint -> :galaxy
      end

    socket =
      socket
      |> assign(%{
        token_attempted?: false,
        token_valid?: AsyncResult.ok(false),
        client: client,
        surveys: [],
        app_section: app_section,
        selected_waypoint_symbol: nil,
        selected_ship_symbol: nil,
        selected_survey_id: nil,
        system: AsyncResult.loading(),
        waypoints: %{},
        agent: AsyncResult.ok(agent_body["data"])
      })
      |> assign_async(:agent_automaton, fn ->
        case SpacetradersClient.AutomationServer.automaton(agent_body["data"]["symbol"]) do
          {:ok, agent_automaton} ->
            {:ok, %{agent_automaton: agent_automaton}}

          _ ->
            {:ok, %{agent_automaton: nil}}
        end
      end)
      |> then(fn socket ->
        case SpacetradersClient.LedgerServer.ledger(agent_body["data"]["symbol"]) do
          {:ok, ledger} ->
            assign(socket, %{ledger: ledger})

          _ ->
            assign(socket, %{ledger: nil})
        end
      end)
      |> assign_async(:system, fn ->
        case Systems.get_system(client, system_symbol) do
          {:ok, s} -> {:ok, %{system: s.body["data"]}}
          err -> err
        end
      end)
      |> assign_async(:marketplaces, fn ->
        case Systems.list_waypoints(client, system_symbol, traits: "MARKETPLACE") do
          {:ok, w} -> {:ok, %{marketplaces: w.body["data"]}}
          err -> err
        end
      end)
      |> assign_async(:shipyards, fn ->
        case Systems.list_waypoints(client, system_symbol, traits: "SHIPYARD") do
          {:ok, w} -> {:ok, %{shipyards: w.body["data"]}}
          err -> err
        end
      end)
      |> assign(:token, token)
      |> assign(:fleet, AsyncResult.loading())
      |> load_fleet()
      |> assign_async(:contracts, fn ->
        {:ok, %{status: 200, body: body}} = Contracts.my_contracts(client)

        {:ok, %{contracts: body["data"]}}
      end)
      |> then(fn socket ->
        case socket.assigns.live_action do
          :waypoint ->
            socket
            |> assign(:waypoint_tab, "info")
            |> assign(:selected_flight_mode, "CRUISE")
            |> assign(:waypoint_symbol, params["waypoint_symbol"])
            |> assign_async(:waypoint, fn ->
              case Systems.get_waypoint(
                     client,
                     system_symbol,
                     params["waypoint_symbol"]
                   ) do
                {:ok, w} -> {:ok, %{waypoint: w.body["data"]}}
                err -> err
              end
            end)
        end
      end)

    {:ok, socket}
  end

  def mount(_params, _token, socket) do
    {:ok, redirect(socket, to: ~p"/login")}
  end

  def handle_params(unsigned_params, _uri, socket) do
    case socket.assigns.live_action do
      :agent ->
        socket =
          assign(socket, :app_section, :agent)

        {:noreply, socket}

      :contract ->
        socket =
          assign(socket, %{
            contract_id: unsigned_params["contract_id"]
          })

        {:noreply, socket}

      :system ->
        socket =
          assign(socket, %{
            system_symbol: unsigned_params["system_symbol"]
          })
          |> load_system()
          |> load_waypoints()

        {:noreply, socket}

      :waypoint ->
        socket =
          if unsigned_params["system_symbol"] == socket.assigns[:system_symbol] do
            socket
          else
            socket
            |> assign(:system_symbol, unsigned_params["system_symbol"])
            |> load_system()
            |> load_waypoints()
          end

        socket = assign(socket, :waypoint_symbol, unsigned_params["waypoint_symbol"])

        {:noreply, socket}

      :ship ->
        socket =
          socket
          |> assign(%{
            selected_ship_symbol: unsigned_params["ship_symbol"],
            system_symbol: unsigned_params["system_symbol"],
            waypoint_symbol: unsigned_params["waypoint_symbol"]
          })
          |> load_system()
          |> load_waypoints()

        {:noreply, socket}

      :fleet ->
        {:noreply, socket}
    end
  end

  defp select_ship(socket, ship_symbol) do
    ship =
      if ship_symbol do
        Enum.find(socket.assigns.fleet.result, fn ship ->
          ship["symbol"] == ship_symbol
        end)
        |> then(fn ship ->
          if is_nil(ship), do: List.first(socket.assigns.fleet.result), else: ship
        end)
      else
        List.first(socket.assigns.fleet.result)
      end

    assign(socket, :selected_ship_symbol, ship["symbol"])
  end

  def handle_event("automation-started", %{}, socket) do
    {:ok, _} =
      DynamicSupervisor.start_child(
        SpacetradersClient.AutomatonSupervisor,
        {SpaceTradersClient.AutomatonServer, [token: socket.assigns.token]}
      )

    {:noreply, socket}
  end

  def handle_event("purchase-fuel", %{"ship-symbol" => ship_symbol}, socket) do
    case Fleet.refuel_ship(socket.assigns.client, ship_symbol) do
      {:ok, %{status: 200, body: body}} ->
        socket = put_flash(socket, :info, "Ship refueled")

        fleet =
          Enum.map(socket.assigns.fleet.result, fn ship ->
            if ship["symbol"] == ship_symbol do
              put_in(ship, ~w(fuel current), get_in(body, ~w(data fuel current)))
            else
              ship
            end
          end)
          |> AsyncResult.ok()

        socket = assign(socket, :fleet, fleet)

        waypoint_symbol =
          Enum.find(socket.assigns.fleet.result, fn ship -> ship["symbol"] == ship_symbol end)
          |> get_in(~w(nav waypointSymbol))

        tx = body["data"]["transaction"]
        {:ok, ts, _} = DateTime.from_iso8601(tx["timestamp"])

        if tx["units"] > 0 do
          {:ok, _ledger} =
            LedgerServer.post_journal(
              body["data"]["agent"]["symbol"],
              ts,
              "#{tx["type"]} #{tx["tradeSymbol"]} × #{tx["units"]} @ #{tx["pricePerUnit"]}/u — #{ship_symbol} @ #{waypoint_symbol}",
              "Fuel",
              "Cash",
              tx["totalPrice"]
            )
        end

        {:noreply, socket}

      {:ok, %{body: %{"error" => %{"message" => message}}}} ->
        socket = put_flash(socket, :error, message)
        {:noreply, socket}
    end
  end

  def handle_event("select-waypoint", %{"waypoint-symbol" => waypoint_symbol}, socket) do
    {:noreply, assign(socket, :selected_waypoint, waypoint_symbol)}
  end

  def handle_event("select-ship", %{"ship-symbol" => ship_symbol}, socket) do
    {:noreply, select_ship(socket, ship_symbol)}
  end

  def handle_event(
        "set-flight-mode",
        %{"ship-symbol" => ship_symbol, "flight-mode" => flight_mode},
        socket
      ) do
    {:ok, %{status: 200, body: body}} =
      Fleet.set_flight_mode(socket.assigns.client, ship_symbol, flight_mode)

    socket =
      update_ship(socket, ship_symbol, fn ship ->
        Map.put(ship, "nav", body["data"])
      end)
      |> put_flash(:success, "Ship #{ship_symbol} now in #{flight_mode} mode")

    {:noreply, socket}
  end

  def handle_event(
        "purchase-ship",
        %{"waypoint-symbol" => waypoint_symbol, "ship-type" => ship_type},
        socket
      ) do
    {:ok, %{status: 201, body: body}} =
      Fleet.purchase_ship(socket.assigns.client, waypoint_symbol, ship_type)

    ship = body["data"]["ship"]
    agent = body["data"]["agent"]

    new_fleet =
      [ship | socket.assigns.fleet.result]
      |> Enum.sort_by(fn s -> s["symbol"] end)

    socket =
      socket
      |> assign(:fleet, AsyncResult.ok(new_fleet))
      |> assign(:agent, AsyncResult.ok(agent))
      |> put_flash(:success, "Ship #{ship["symbol"]} has been purchased")

    tx = body["data"]["transaction"]

    {:ok, ts, _} = DateTime.from_iso8601(tx["timestamp"])

    {:ok, _ledger} =
      LedgerServer.post_journal(
        tx["agentSymbol"],
        ts,
        "BUY #{tx["shipType"]} × 1 @ #{tx["price"]}/u @ #{tx["waypointSymbol"]}",
        "Fleet",
        "Cash",
        tx["price"]
      )

    PubSub.broadcast(@pubsub, "agent:" <> body["data"]["agent"]["symbol"], :fleet_updated)

    {:noreply, socket}
  end

  def handle_event(
        "select-waypoint",
        %{"system-symbol" => system_symbol, "waypoint-symbol" => waypoint_symbol},
        socket
      ) do
    {:noreply,
     push_patch(socket, to: "/game/systems/#{system_symbol}/waypoints/#{waypoint_symbol}")}
  end

  def handle_event(
        "deliver-contract-cargo",
        %{
          "contract-id" => contract_id,
          "ship-symbol" => ship_symbol,
          "trade-symbol" => trade_symbol,
          "units" => quantity
        },
        socket
      ) do
    client = socket.assigns.client

    socket =
      start_async(socket, :deliver_contract, fn ->
        {:ok, %{status: 200, body: body}} =
          Contracts.deliver_cargo(client, contract_id, ship_symbol, trade_symbol, quantity)

        %{
          data: body["data"],
          ship_symbol: ship_symbol,
          contract_id: contract_id
        }
      end)

    {:noreply, socket}
  end

  def handle_event("extract-resources", %{"ship-symbol" => ship_symbol}, socket) do
    client = socket.assigns.client

    selected_survey =
      Enum.find(socket.assigns.surveys, fn s ->
        s["signature"] == socket.assigns[:selected_survey_id]
      end)

    socket =
      start_async(socket, :extract_resources, fn ->
        {:ok, %{status: 201, body: body}} =
          if selected_survey do
            Fleet.extract_resources(client, ship_symbol, selected_survey)
          else
            Fleet.extract_resources(client, ship_symbol)
          end

        %{
          ship_symbol: ship_symbol,
          data: body["data"]
        }
      end)

    {:noreply, socket}
  end

  def handle_event("create-survey", %{"ship-symbol" => ship_symbol}, socket) do
    client = socket.assigns.client

    socket =
      start_async(socket, :create_survey, fn ->
        {:ok, %{status: 201, body: body}} = Fleet.create_survey(client, ship_symbol)

        %{
          ship_symbol: ship_symbol,
          data: body["data"]
        }
      end)

    {:noreply, socket}
  end

  def handle_event("survey-loaded", survey, socket) do
    {:ok, survey_exp, _} = DateTime.from_iso8601(survey["expiration"])

    if DateTime.before?(survey_exp, DateTime.utc_now()) do
      {:noreply, socket}
    else
      {:noreply, assign(socket, :surveys, [survey | socket.assigns.surveys])}
    end
  end

  def handle_event("survey-selected", %{"value" => survey_id}, socket) do
    {:noreply, assign(socket, :selected_survey_id, survey_id)}
  end

  def handle_event(
        "sell-cargo",
        %{
          "ship-symbol" => ship_symbol,
          "trade-symbol" => trade_symbol,
          "units" => quantity
        },
        socket
      ) do
    client = socket.assigns.client

    socket =
      start_async(socket, :sell_cargo, fn ->
        {:ok, resp} = Fleet.sell_cargo(client, ship_symbol, trade_symbol, quantity)

        resp
      end)

    {:noreply, socket}
  end

  def handle_event(
        "jettison-cargo",
        %{
          "ship-symbol" => ship_symbol,
          "item-symbol" => trade_symbol,
          "units" => quantity
        },
        socket
      ) do
    client = socket.assigns.client

    socket =
      start_async(socket, :jettison_cargo, fn ->
        {:ok, %{status: 200, body: body}} =
          Fleet.jettison_cargo(client, ship_symbol, trade_symbol, quantity)

        %{
          ship_symbol: ship_symbol,
          data: body["data"]
        }
      end)

    {:noreply, socket}
  end

  def handle_async(:load_fleet, {:ok, result}, socket) do
    %AsyncResult{} = fleet_result = socket.assigns.fleet

    prev_fleet =
      if fleet_result.ok? do
        socket.assigns.fleet.result
      else
        []
      end

    new_fleet =
      (result.data ++ prev_fleet)
      |> Enum.sort_by(fn ship -> ship["symbol"] end)

    socket =
      assign(socket, :fleet, AsyncResult.ok(new_fleet))

    socket =
      if Enum.count(socket.assigns.fleet.result) < result.meta["total"] do
        load_fleet(socket, result.meta["page"] + 1)
      else
        socket
      end

    {:noreply, socket}
  end

  def handle_async(:deliver_contract, {:ok, result}, socket) do
    socket =
      socket
      |> update_ship(result.ship_symbol, fn ship ->
        Map.put(ship, "cargo", result.data["cargo"])
      end)
      |> update_contract(result.contract_id, fn _contract ->
        result.data["contract"]
      end)

    {:noreply, socket}
  end

  def handle_async(:sell_cargo, {:ok, %{status: 201, body: body}}, socket) do
    tx = body["data"]["transaction"]
    ship_symbol = tx["shipSymbol"]
    cargo = body["data"]["cargo"]
    agent = body["data"]["agent"]

    socket =
      socket
      |> update_ship(ship_symbol, fn ship ->
        Map.put(ship, "cargo", cargo)
      end)
      |> assign(:agent, AsyncResult.ok(agent))
      |> put_flash(:success, "Sold items for #{tx["totalPrice"]} credits")

    {:ok, ts, _} = DateTime.from_iso8601(tx["timestamp"])

    {:ok, _ledger} =
      LedgerServer.post_journal(
        body["data"]["agent"]["symbol"],
        ts,
        "#{tx["type"]} #{tx["tradeSymbol"]} × #{tx["units"]} @ #{tx["pricePerUnit"]}/u — #{ship_symbol} @ #{tx["waypointSymbol"]}",
        "Cash",
        "Merchandise",
        tx["totalPrice"]
      )

    {:ok, _ledger} =
      LedgerServer.post_journal(
        body["data"]["agent"]["symbol"],
        ts,
        "#{tx["type"]} #{tx["tradeSymbol"]} × #{tx["units"]} @ #{tx["pricePerUnit"]}/u — #{ship_symbol} @ #{tx["waypointSymbol"]}",
        "Cost of Merchandise Sold",
        "Merchandise",
        tx["totalPrice"]
      )

    {:noreply, socket}
  end

  def handle_async(:sell_cargo, {:ok, %{body: %{"error" => %{"message" => message}}}}, socket) do
    socket =
      socket
      |> put_flash(:error, message)

    {:noreply, socket}
  end

  def handle_async(:jettison_cargo, {:ok, result}, socket) do
    socket =
      socket
      |> update_ship(result.ship_symbol, fn ship ->
        Map.put(ship, "cargo", result.data["cargo"])
      end)
      |> put_flash(:success, "Cargo jettisoned")

    {:noreply, socket}
  end

  def handle_async(:extract_resources, {:ok, result}, socket) do
    yield = result.data["extraction"]["yield"]

    socket =
      socket
      |> update_ship(result.ship_symbol, fn ship ->
        ship
        |> Map.put("cargo", result.data["cargo"])
        |> Map.put("cooldown", result.data["cooldown"])
      end)
      |> put_flash(:success, "Extracted #{yield["units"]} units of #{yield["symbol"]}")

    {:noreply, socket}
  end

  def handle_async(:create_survey, {:ok, result}, socket) do
    socket =
      assign(socket, :surveys, result.data["surveys"] ++ socket.assigns.surveys)
      |> then(fn socket ->
        Enum.reduce(result.data["surveys"], socket, fn survey, socket ->
          push_event(socket, "survey-completed", survey)
        end)
      end)
      |> put_flash(:success, "Survey created")
      |> update_ship(result.ship_symbol, fn ship ->
        Map.put(ship, "cooldown", result.data["cooldown"])
      end)

    {:noreply, socket}
  end

  def handle_async(:load_waypoints, {:ok, results}, socket) do
    socket =
      Enum.reduce(results.data, socket, fn waypoint, socket ->
        update(socket, :waypoints, fn waypoints ->
          Map.put(waypoints, waypoint["symbol"], waypoint)
        end)
      end)

    socket =
      if Enum.count(socket.assigns.waypoints) < results.meta["total"] do
        load_waypoints(socket, results.meta["page"] + 1)
      else
        socket
      end

    {:noreply, socket}
  end

  def handle_async(:load_ship, {:ok, result}, socket) do
    socket =
      update_ship(socket, Map.fetch!(result.data, "symbol"), fn _ship ->
        result.data
      end)

    {:noreply, socket}
  end

  def handle_info({:ledger_updated, ledger}, socket) do
    socket =
      assign(socket, :ledger, ledger)

    {:noreply, socket}
  end

  def handle_info({:agent_updated, agent}, socket) do
    socket =
      assign(socket, :agent, AsyncResult.ok(agent))

    {:noreply, socket}
  end

  def handle_info({:ship_updated, ship_symbol, updated_ship}, %Socket{} = socket) do
    socket =
      update_ship(socket, ship_symbol, fn _ship ->
        updated_ship
      end)

    {:noreply, socket}
  end

  def handle_info({:ship_nav_updated, ship_symbol, nav}, socket) do
    socket =
      update_ship(socket, ship_symbol, fn ship ->
        Map.put(ship, "nav", nav)
      end)

    {:noreply, socket}
  end

  def handle_info({:ship_fuel_updated, ship_symbol, fuel}, socket) do
    socket =
      update_ship(socket, ship_symbol, fn ship ->
        Map.put(ship, "fuel", fuel)
      end)

    {:noreply, socket}
  end

  def handle_info({:ship_cargo_updated, ship_symbol, cargo}, socket) do
    socket =
      update_ship(socket, ship_symbol, fn ship ->
        Map.put(ship, "cargo", cargo)
      end)

    {:noreply, socket}
  end

  def handle_info({:ship_cooldown_updated, ship_symbol, cooldown}, socket) do
    socket =
      update_ship(socket, ship_symbol, fn ship ->
        Map.put(ship, "cooldown", cooldown)
      end)

    {:noreply, socket}
  end

  def handle_info({:travel_cooldown_expired, ship_symbol}, socket) do
    client = socket.assigns.client

    socket =
      start_async(socket, :load_ship, fn ->
        {:ok, result} = Fleet.get_ship(client, ship_symbol)

        %{data: result.body["data"]}
      end)

    {:noreply, socket}
  end

  def handle_info({:automaton_updated, automaton}, socket) do
    {:noreply, assign(socket, :agent_automaton, AsyncResult.ok(automaton))}
  end

  def handle_info(_, socket) do
    {:noreply, socket}
  end

  defp update_ship(fleet, ship_symbol, ship_update_fn) when is_list(fleet) do
    i =
      Enum.find_index(fleet, fn ship ->
        ship["symbol"] == ship_symbol
      end)

    if is_integer(i) do
      List.update_at(fleet, i, ship_update_fn)
    else
      fleet
    end
  end

  defp update_ship(%Phoenix.LiveView.Socket{} = socket, ship_symbol, ship_update_fn) do
    fleet = update_ship(socket.assigns.fleet.result, ship_symbol, ship_update_fn)

    assign(socket, :fleet, AsyncResult.ok(fleet))
  end

  defp update_contract(contracts, contract_id, contract_update_fn) when is_list(contracts) do
    i =
      Enum.find_index(contracts, fn contract ->
        contract["id"] == contract_id
      end)

    if is_integer(i) do
      List.update_at(contracts, i, contract_update_fn)
    else
      contracts
    end
  end

  defp update_contract(%Phoenix.LiveView.Socket{} = socket, contract_id, contract_update_fn) do
    contracts = update_contract(socket.assigns.contracts, contract_id, contract_update_fn)

    assign(socket, :contracts, contracts)
  end

  defp load_system(socket) do
    symbol = socket.assigns.system_symbol
    client = socket.assigns.client

    socket =
      assign_async(socket, :system, fn ->
        case Systems.get_system(client, symbol) do
          {:ok, %{status: 200, body: body}} ->
            system =
              body["data"]
              |> Map.update!("waypoints", fn waypoints ->
                Enum.sort_by(waypoints, & &1["symbol"])
              end)

            {:ok, %{system: system}}

          {:ok, resp} ->
            {:error, resp}

          err ->
            err
        end
      end)

    socket
  end

  defp load_waypoints(socket, page \\ 1) when is_integer(page) and page > 0 do
    symbol = socket.assigns.system_symbol
    client = socket.assigns.client

    start_async(socket, :load_waypoints, fn ->
      case Systems.list_waypoints(client, symbol, page: page) do
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

  def load_fleet(socket, page \\ 1) do
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

  defp load_contract(socket) do
    id = socket.assigns.contract_id
    client = socket.assigns.client

    socket =
      assign_async(socket, :contract, fn ->
        case Contracts.get_contract(client, id) do
          {:ok, %{status: 200, body: body}} ->
            {:ok, %{contract: body["data"]}}

          {:ok, resp} ->
            {:error, resp}

          err ->
            err
        end
      end)

    socket
  end
end
