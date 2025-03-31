defmodule SpacetradersClientWeb.GameLive do
  use SpacetradersClientWeb, :live_view

  alias Phoenix.LiveView.Socket
  alias Phoenix.LiveView.AsyncResult
  alias SpacetradersClient.Fleet
  alias SpacetradersClient.Contracts
  alias SpacetradersClient.Fleet
  alias SpacetradersClient.Repo
  alias SpacetradersClient.Finance
  alias SpacetradersClient.Game.Ship
  alias SpacetradersClient.Game.System
  alias SpacetradersClient.Game.Waypoint

  alias Phoenix.PubSub

  import Ecto.Query, except: [update: 3]

  require Logger

  @pubsub SpacetradersClient.PubSub

  attr :system_symbol, :string, default: nil
  attr :waypoint_symbol, :string, default: nil

  def render(assigns) do
    ~H"""
      <.live_component
        module={SpacetradersClientWeb.OrbitalsMenuComponent}
        id="orbitals"
        agent_symbol={@agent.result.symbol}
        system_symbol={@system_symbol}
        waypoint_symbol={@waypoint_symbol}
        ship_symbol={@ship_symbol}
      >
        <%= case @live_action do %>
          <% :ship -> %>
            <.live_component
              module={SpacetradersClientWeb.FleetComponent}
              id={"ship-#{@ship_symbol}"}
              ship_symbol={@ship_symbol}
            />

          <% :waypoint -> %>
            <.live_component
              id={@waypoint_symbol}
              module={SpacetradersClientWeb.WaypointComponent}
              agent={@agent.result}
              agent_symbol={@agent_symbol}
              waypoint_symbol={@waypoint_symbol}
              system_symbol={@system_symbol}
            />

        <% end %>
      </.live_component>
    """
  end

  on_mount {SpacetradersClientWeb.GameLoader, :agent}

  def mount(params, _session, socket) do
    agent_symbol = socket.assigns.agent.result.symbol

    PubSub.subscribe(@pubsub, "agent:#{agent_symbol}")

    app_section =
      case socket.assigns.live_action do
        :agent -> :agent
        :waypoint -> :galaxy
        :ship -> :fleet
      end

    ship_symbol = params["ship_symbol"]

    {system_symbol, waypoint_symbol} =
      if is_binary(ship_symbol) do
        ship = Repo.get(Ship, ship_symbol) |> Repo.preload(:nav_waypoint)

        {ship.nav_waypoint.system_symbol, ship.nav_waypoint_symbol}
      else
        system_symbol = params["system_symbol"]
        waypoint_symbol = params["waypoint_symbol"]

        {system_symbol, waypoint_symbol}
      end

    socket =
      socket
      |> assign(%{
        system_symbol: system_symbol,
        waypoint_symbol: waypoint_symbol,
        ship_symbol: ship_symbol,
        token_attempted?: false,
        token_valid?: AsyncResult.ok(false),
        surveys: [],
        app_section: app_section,
        selected_waypoint_symbol: nil,
        selected_ship_symbol: nil,
        selected_survey_id: nil,
        marketplaces: AsyncResult.loading(),
        marketplace: AsyncResult.loading(),
        shipyards: AsyncResult.loading(),
        shipyard: AsyncResult.loading(),
        construction_site: AsyncResult.loading()
      })
      |> assign_async(:fleet, fn ->
        {:ok,
         %{
           fleet:
             Repo.all(from s in Ship, where: [agent_symbol: ^agent_symbol])
             |> Repo.preload([:nav_waypoint])
         }}
      end)
      |> assign_async(:system, fn ->
        {:ok,
         %{
           system:
             Repo.get(System, system_symbol)
             |> Repo.preload(waypoints: [:orbits, :modifiers, :traits])
         }}
      end)
      |> assign_async(:waypoint, fn ->
        {:ok,
         %{
           waypoint:
             Repo.get(Waypoint, waypoint_symbol) |> Repo.preload([:orbits, :modifiers, :traits])
         }}
      end)

    {:ok, socket}
  end

  def handle_params(%{"ship_symbol" => ship_symbol}, _uri, socket) do
    {system_symbol, waypoint_symbol} =
      Repo.one(
        from s in Ship,
          join: wp in assoc(s, :nav_waypoint),
          where: [symbol: ^ship_symbol],
          select: {wp.system_symbol, s.nav_waypoint_symbol}
      )

    socket =
      socket
      |> assign(%{
        ship_symbol: ship_symbol,
        system_symbol: system_symbol,
        waypoint_symbol: waypoint_symbol
      })

    {:noreply, socket}
  end

  def handle_params(
        %{"system_symbol" => system_symbol, "waypoint_symbol" => waypoint_symbol},
        _uri,
        socket
      ) do
    socket =
      socket
      |> assign(%{
        system_symbol: system_symbol,
        waypoint_symbol: waypoint_symbol
      })

    {:noreply, socket}
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
            Finance.post_journal(
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
      Finance.post_journal(
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
      Finance.post_journal(
        body["data"]["agent"]["symbol"],
        ts,
        "#{tx["type"]} #{tx["tradeSymbol"]} × #{tx["units"]} @ #{tx["pricePerUnit"]}/u — #{ship_symbol} @ #{tx["waypointSymbol"]}",
        "Cash",
        "Merchandise",
        tx["totalPrice"]
      )

    {:ok, _ledger} =
      Finance.post_journal(
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

  # def handle_info({:travel_cooldown_expired, ship_symbol}, socket) do
  #   client = socket.assigns.client

  #   socket =
  #     start_async(socket, :load_ship, fn ->
  #       {:ok, result} = Fleet.get_ship(client, ship_symbol)

  #       %{data: result.body["data"]}
  #     end)

  #   {:noreply, socket}
  # end

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
end
