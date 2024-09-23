defmodule SpacetradersClientWeb.GameLive do
  alias SpacetradersClient.Fleet
  use SpacetradersClientWeb, :live_view

  alias SpacetradersClient.Agents
  alias SpacetradersClient.Client

  attr :selected_ship, :string, default: nil
  attr :system_symbol, :string, default: nil
  attr :waypoint_symbol, :string, default: nil

  def render(assigns) do
    ~H"""
    <div class="flex flex-row min-h-screen">
      <ul class="menu bg-base-300 w-72 grow">
        <li>
          <.link
            class={if @live_action == :agent, do: ["active"], else: []}
            patch={~p"/game/agent"}
          >
            <.icon name="hero-user" />
            <span class="font-mono"><%= @agent["symbol"] %></span>
            <span>
              <.icon name="hero-circle-stack" class="w-4 h-4" />
              <%= @agent["credits"] %>
            </span>
          </.link>
        </li>
        <li>
          <details {if @live_action == :fleet, do: %{open: true}, else: %{}}>
            <summary>
              <.icon name="hero-rocket-launch" />
              <span>Fleet</span>
              <span><%= @agent["shipCount"] %></span>
            </summary>
            <ul>
              <%= for ship <- @fleet do %>
                <li>
                  <.link
                    class={if @selected_ship == ship["symbol"], do: ["active"], else: []}
                    patch={~p"/game/fleet/#{ship["symbol"]}"}
                  >
                    <%= ship["registration"]["name"] %>
                  </.link>
                </li>
              <% end %>
            </ul>
          </details>
        </li>
        <li>
          <.link
            class={if @live_action == :systems, do: ["active"], else: []}
            patch={~p"/game/systems"}
          >
            <.icon name="hero-globe-alt" />
            <span>Navigation</span>
          </.link>
        </li>
      </ul>
      <%= case @live_action do %>
        <% :fleet -> %>
          <.live_component module={SpacetradersClientWeb.ShipComponent} id={"ship-#{@selected_ship}"} client={@client} ship={Enum.find(@fleet, &(&1["symbol"] == @selected_ship))} />
        <% :systems -> %>
          <.live_component
            module={SpacetradersClientWeb.SystemsComponent}
            id="systems"
            client={@client}
            agent={@agent}
            fleet={@fleet}
            system_symbol={@system_symbol}
            waypoint_symbol={@waypoint_symbol}
            ship_symbol={@selected_ship}
          />
        <% _ -> %>
          <.live_component module={SpacetradersClientWeb.AgentComponent} id="my-agent" client={@client} agent={@agent} />
      <% end %>

    </div>

    """

    #   <form phx-submit="save-token">
    #     <article class="form-control">
    #       <label class="input input-bordered flex items-center gap-2">SpaceTraders token
    #         <input name="spacetraders-token" type="password" class="grow" />
    #       </label>
    #     </article>
    #     <button class="btn btn-primary">Play SpaceTraders</button>
    #   </form>
    #   <% end %>
  end

  def mount(_params, _session, socket) do
    token = System.fetch_env!("SPACETRADERS_TOKEN")
    client = Client.new(token)
    {:ok, %{status: 200, body: body}} = Agents.my_agent(client)
    {:ok, %{status: 200, body: ships_body}} = Fleet.list_ships(client)

    socket = assign(socket, %{
      client: client,
      agent: body["data"],
      fleet: ships_body["data"],
    })
    {:ok, socket}
  end

  def handle_params(unsigned_params, _uri, socket) do
    case socket.assigns.live_action do
      :fleet ->
        socket = select_ship(socket, unsigned_params["ship_symbol"])
        {:noreply, socket}

      :systems ->
        socket = assign(socket, %{
          system_symbol: unsigned_params["system_symbol"],
          waypoint_symbol: unsigned_params["waypoint_symbol"]
        })
        {:noreply, socket}
      _ ->
        {:noreply, socket}
    end
  end

  defp select_ship(socket, ship_symbol) do
    ship =
      if ship_symbol do
        Enum.find(socket.assigns.fleet, fn ship ->
          ship["symbol"] == ship_symbol
        end)
        |> then(fn ship ->
          if is_nil(ship), do: List.first(socket.assigns.fleet), else: ship
        end)
      else
        List.first(socket.assigns.fleet)
      end

    assign(socket, :selected_ship, ship["symbol"])
  end

  def handle_event("purchase-fuel", %{"ship-symbol" => ship_symbol}, socket) do
    {:ok, %{status: 200, body: body}} = Fleet.refuel_ship(socket.assigns.client, ship_symbol)

    socket = put_flash(socket, :info, "Ship refueled")

    fleet =
      Enum.map(socket.assigns.fleet, fn ship ->
        if ship["symbol"] == ship_symbol do
          put_in(ship, ~w(fuel current), get_in(body, ~w(data fuel current)))
        else
          ship
        end
      end)

    socket = assign(socket, :fleet, fleet)

    {:noreply, socket}
  end

  def handle_event("select-ship", %{"ship-symbol" => ship_symbol}, socket) do
    {:noreply, select_ship(socket, ship_symbol)}
  end

  def handle_event("dock-ship", %{"ship-symbol" => ship_symbol}, socket) do
    {:ok, %{status: 200, body: body}} = Fleet.dock_ship(socket.assigns.client, ship_symbol)

    socket =
      update_ship(socket, ship_symbol, fn ship ->
        Map.put(ship, "nav", body["data"]["nav"])
      end)
      |> put_flash(:info, "Ship #{ship_symbol} docked successfully")

    {:noreply, socket}
  end

  def handle_event("orbit-ship", %{"ship-symbol" => ship_symbol}, socket) do
    {:ok, %{status: 200, body: body}} = Fleet.orbit_ship(socket.assigns.client, ship_symbol)

    socket =
      update_ship(socket, ship_symbol, fn ship ->
        Map.put(ship, "nav", body["data"]["nav"])
      end)
      |> put_flash(:info, "Ship #{ship_symbol} undocked successfully")

    {:noreply, socket}
  end

  def handle_event("select-waypoint", %{"system-symbol" => system_symbol, "waypoint-symbol" => waypoint_symbol}, socket) do
    {:noreply, push_patch(socket, to: "/game/systems/#{system_symbol}/waypoints/#{waypoint_symbol}")}
  end

  defp update_ship(socket, ship_symbol, ship_update_fn) do
    i = Enum.find_index(socket.assigns.fleet, fn ship ->
      ship["symbol"] == ship_symbol
    end)

    fleet = List.update_at(socket.assigns.fleet, i, ship_update_fn)

    assign(socket, :fleet, fleet)
  end
end
