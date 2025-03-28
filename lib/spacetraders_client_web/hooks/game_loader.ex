defmodule SpacetradersClientWeb.GameLoader do
  use Phoenix.VerifiedRoutes, endpoint: SpacetradersClientWeb.Endpoint, router: SpacetradersClientWeb.Router
  alias Phoenix.Component
  alias Phoenix.LiveView
  alias Phoenix.LiveView.AsyncResult
  alias SpacetradersClient.Client
  alias SpacetradersClient.Agents
  alias SpacetradersClient.Fleet
  alias SpacetradersClient.Systems
  alias SpacetradersClient.GameServer

  import Phoenix.LiveView

  def on_mount(:agent, _params, %{"token" => token}, socket) do
    client = Client.new(token)

    {:ok, %{status: 200, body: agent_body}} = Agents.my_agent(client)
    agent_symbol = agent_body["data"]["symbol"]

    {:ok, _} = GameServer.ensure_started(agent_symbol, token)
    :ok = SpacetradersClient.LedgerServer.ensure_started(agent_symbol)

    socket =
      socket
      |> Component.assign(%{
        token: token,
        client: client,
        agent: AsyncResult.ok(agent_body["data"])
      })
      |> LiveView.assign_async(:agent_automaton, fn ->
        case SpacetradersClient.AutomationServer.automaton(agent_symbol) do
          {:ok, agent_automaton} ->
            {:ok, %{agent_automaton: agent_automaton}}

          {:error, reason} ->
            dbg(reason)
            {:ok, %{agent_automaton: nil}}
        end
      end)
      |> LiveView.assign_async(:ledger, fn ->
        case SpacetradersClient.LedgerServer.ledger(agent_symbol) do
          {:ok, ledger} ->
            {:ok, %{ledger: ledger}}

          {:error, reason} ->
            dbg(reason)
            {:error, reason}
        end
      end)

    {:cont, socket}
  end

  def mount(:agent, _params, _token, socket) do
    {:halt, redirect(socket, to: ~p"/login")}
  end


  def attach_params_handler(socket) do
    socket
    |> Component.assign_new(:fleet, fn -> AsyncResult.loading() end)
    |> Component.assign_new(:system, fn -> AsyncResult.loading() end)
    |> Component.assign_new(:waypoint, fn -> AsyncResult.loading() end)
    |> Component.assign_new(:ship, fn -> AsyncResult.loading() end)
    |> Component.assign_new(:waypoint, fn -> AsyncResult.loading() end)
    |> Component.assign_new(:marketplaces, fn -> AsyncResult.loading() end)
    |> Component.assign_new(:marketplace, fn -> AsyncResult.loading() end)
    |> Component.assign_new(:shipyards, fn -> AsyncResult.loading() end)
    |> Component.assign_new(:shipyard, fn -> AsyncResult.loading() end)
    |> Component.assign_new(:construction_site, fn -> AsyncResult.loading() end)
    |> LiveView.attach_hook(:game_params_handler, :handle_params, &handle_game_params/3)
  end

  def handle_game_params(params, _uri, socket) do
    socket =
      socket
      |> Component.assign(%{
        system_symbol: params["system_symbol"],
        waypoint_symbol: params["waypoint_symbol"],
        ship_symbol: params["ship_symbol"]
      })
      |> then(fn socket ->
        if socket.assigns.fleet.ok? do
          ship = Enum.find(socket.assigns.fleet.result, fn s -> s["symbol"] == socket.assigns.ship_symbol end)

          if !is_nil(ship) && ship["symbol"] != socket.assigns[:ship_symbol] do
            system_symbol = ship["nav"]["systemSymbol"]
            waypoint_symbol = ship["nav"]["waypointSymbol"]

            socket
            |> Component.assign(%{
              ship: AsyncResult.ok(socket.assigns.ship, ship),
              system_symbol: system_symbol,
              waypoint_symbol: waypoint_symbol
            })

          else
            socket
          end
        else
          socket
        end
      end)
      |> then(fn socket ->
        if is_binary(socket.assigns[:system_symbol]) do
          if (socket.assigns.system.ok? && socket.assigns.system.result["symbol"] == socket.assigns[:system_symbol]) do
            socket
          else
            load_system(socket, socket.assigns.system_symbol)
          end
        else
          socket
        end
      end)
      |> then(fn socket ->
        if is_binary(socket.assigns[:waypoint_symbol]) do
          if (socket.assigns.waypoint.ok? && socket.assigns.waypoint.result["symbol"] == socket.assigns[:waypoint_symbol]) do
            socket
          else
            socket
            |> load_waypoint(socket.assigns.system_symbol, socket.assigns.waypoint_symbol)
          end
        else
          socket
        end
      end)

    {:cont, socket}
  end

  def load_fleet(socket, page \\ 1) do
    client = socket.assigns.client

    if is_binary(socket.assigns[:ship_symbol]) do
      socket
      |> Component.assign(%{
        ship: AsyncResult.loading(),
        system: AsyncResult.loading(),
        waypoint: AsyncResult.loading(),
        marketplaces: AsyncResult.loading(),
        marketplace: AsyncResult.loading(),
        shipyards: AsyncResult.loading(),
        shipyard: AsyncResult.loading(),
        construction_site: AsyncResult.loading()
      })
    else
      socket
    end
    |> Component.assign(%{
      fleet: AsyncResult.loading(),
    })
    |> LiveView.start_async(:load_fleet, fn ->
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
    |> LiveView.detach_hook(:load_fleet, :handle_async)
    |> LiveView.attach_hook(:load_fleet, :handle_async, &handle_async/3)
  end

  def load_system(socket, system_symbol) when is_binary(system_symbol) do
    client = socket.assigns.client

    socket
    |> Component.assign(%{
      system: AsyncResult.loading([:system]),
      marketplaces: AsyncResult.loading([:marketplaces]),
      shipyards: AsyncResult.loading([:shipyards]),
    })
    |> LiveView.start_async(:load_system, fn ->
      case Systems.get_system(client, system_symbol) do
        {:ok, s} -> %{data: s.body["data"]}
        err -> err
      end
    end)
    |> LiveView.detach_hook(:load_system, :handle_async)
    |> LiveView.attach_hook(:load_system, :handle_async, &handle_async/3)
  end

  def unload_system(socket) do
    socket
    |> Component.assign(%{
      system: AsyncResult.loading(),
      marketplaces: AsyncResult.loading(),
      shipyards: AsyncResult.loading(),
    })
    |> unload_waypoint()
  end

  def load_waypoint(socket, system_symbol, waypoint_symbol) when is_binary(system_symbol) and is_binary(waypoint_symbol) do
    client = socket.assigns.client

    socket
    |> unload_waypoint()
    |> LiveView.start_async({:load_waypoint, system_symbol, waypoint_symbol}, fn ->
      case Systems.get_waypoint(client, system_symbol, waypoint_symbol) do
        {:ok, %{body: body, status: 200}} -> %{data: body["data"]}
        {:ok, %{body: body}} -> {:error, body["error"]}
        err -> err
      end
    end)
    |> LiveView.detach_hook({:load_waypoint, system_symbol, waypoint_symbol}, :handle_async)
    |> LiveView.attach_hook({:load_waypoint, system_symbol, waypoint_symbol}, :handle_async, &handle_async/3)
  end

  def unload_waypoint(socket) do
    socket
    |> Component.assign(%{
      waypoint: AsyncResult.loading(),
      marketplace: AsyncResult.loading(),
      shipyard: AsyncResult.loading(),
      construction_site: AsyncResult.loading()
    })
  end


  def handle_async(:load_fleet, {:ok, result}, socket) do
    page = Map.fetch!(result.meta, "page")

    socket =
      if page == 1 do
        Component.assign(socket, :fleet, AsyncResult.loading(result.data))
      else
        Component.assign(
          socket,
          :fleet,
          AsyncResult.loading(socket.assigns.fleet, socket.assigns.fleet.loading ++ result.data)
        )
      end

    socket =
      if Enum.count(socket.assigns.fleet.loading) < Map.fetch!(result.meta, "total") do
        load_fleet(socket, page + 1)
      else
        Component.assign(
          socket,
          :fleet,
          AsyncResult.ok(socket.assigns.fleet, socket.assigns.fleet.loading)
        )
        |> then(fn socket ->
          if ship_symbol = socket.assigns[:ship_symbol] do
            ship = Enum.find(socket.assigns.fleet.result, fn s -> s["symbol"] == ship_symbol end)
            system_symbol = ship["nav"]["systemSymbol"]
            waypoint_symbol = ship["nav"]["waypointSymbol"]

            socket
            |> Component.assign(:ship, AsyncResult.ok(socket.assigns.ship, ship))
            |> load_system(system_symbol)
            |> load_waypoint(system_symbol, waypoint_symbol)
          else
            socket
          end
        end)
      end

    {:halt, socket}
  end


  def handle_async(:load_system, {:ok, result}, socket) do
    client = socket.assigns.client
    system_symbol = result.data["symbol"]

    socket =
      socket
      |> Component.assign(:system, AsyncResult.ok(socket.assigns.system, result.data))
      |> LiveView.assign_async(:marketplaces, fn ->
        case Systems.list_waypoints(client, system_symbol, traits: "MARKETPLACE") do
          {:ok, w} -> {:ok, %{marketplaces: w.body["data"]}}
          err -> err
        end
      end)
      |> LiveView.assign_async(:shipyards, fn ->
        case Systems.list_waypoints(client, system_symbol, traits: "SHIPYARD") do
          {:ok, w} -> {:ok, %{shipyards: w.body["data"]}}
          err -> err
        end
      end)

    {:halt, socket}
  end

  def handle_async({:load_waypoint, system_symbol, waypoint_symbol}, {:ok, result}, socket) do
    client = socket.assigns.client
    waypoint = result.data

    socket =
      socket
      |> Component.assign(:waypoint, AsyncResult.ok(socket.assigns.waypoint, waypoint))
      |> then(fn socket ->
        if Enum.find(waypoint["traits"], fn trait -> trait["symbol"] == "MARKETPLACE" end) do
          LiveView.assign_async(socket, :marketplace, fn ->
            case Systems.get_market(client, system_symbol, waypoint_symbol) do
              {:ok, m} -> {:ok, %{marketplace: m.body["data"]}}
              err -> err
            end
          end)
        else
          Component.assign(socket, :marketplace, AsyncResult.ok(nil))
        end
      end)
      |> then(fn socket ->
        if Enum.find(waypoint["traits"], fn trait -> trait["symbol"] == "SHIPYARD" end) do
          LiveView.assign_async(socket, :shipyard, fn ->
            case Systems.get_shipyard(client, system_symbol, waypoint_symbol) do
              {:ok, s} -> {:ok, %{shipyard: s.body["data"]}}
              err -> err
            end
          end)
        else
          Component.assign(socket, :shipyard, AsyncResult.ok(nil))
        end
      end)
      |> then(fn socket ->
        if waypoint["isUnderConstruction"] do
          LiveView.assign_async(socket, :construction_site, fn ->
            case Systems.get_construction_site(client, system_symbol, waypoint_symbol) do
              {:ok, %{status: 200, body: body}} ->
                {:ok, %{construction_site: body["data"]}}

              {:ok, %{status: 404}} ->
                {:ok, %{construction_site: nil}}
            end
          end)
        else
          Component.assign(socket, :construction_site, AsyncResult.ok(nil))
        end
      end)

    {:halt, socket}
  end

  def handle_async(_event, _params, socket) do
    {:cont, socket}
  end

end
