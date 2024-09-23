defmodule SpacetradersClientWeb.ShipComponent do
  use SpacetradersClientWeb, :live_component

  alias SpacetradersClient.Systems

  def render(assigns) do
    ~H"""
    <section class="p-8 h-full w-full flex flex-col">
      <header class="mb-4 shrink-0">
        <h2 class="text-neutral-500">Ship</h2>
        <h1 class="text-2xl"><%= @ship["registration"]["name"] %></h1>
      </header>

      <section class="stats mb-8 shrink-0">
        <div class="stat">
          <h3 class="stat-title">Role</h3>
          <div class="stat-value"><%= @ship["registration"]["role"] %></div>
          <div class="stat-desc invisible"></div>
          <div class="stat-actions invisible">
            <button class="btn btn-neutral" disabled></button>
          </div>
        </div>

        <div class="stat">
          <h3 class="stat-title">Navigation</h3>
          <%= case @ship["nav"]["status"] do %>
            <% "IN_TRANSIT" -> %>
              <div class="stat-value">
                In transit
              </div>
              <div class="stat-desc">
                Traveling to <%= get_in(@ship, ~w(nav route destination symbol)) %>
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
                Orbiting <%= get_in(@ship, ~w(nav waypointSymbol)) %>
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
                Docked at <%= get_in(@ship, ~w(nav waypointSymbol)) %>
              </div>
              <div class="stat-actions">
                <button phx-click="orbit-ship" phx-value-ship-symbol={@ship["symbol"]} class="btn btn-neutral">Undock</button>
                <button class="btn btn-neutral" disabled>Dock</button>
              </div>
          <% end %>
        </div>

        <div class="stat">
          <%
            fuel_current = @ship["fuel"]["current"]
            fuel_capacity = @ship["fuel"]["capacity"]
            fuel_percent = trunc(Float.ceil(fuel_current / fuel_capacity * 100))
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
          <div class="stat-actions">
            <button class="btn btn-neutral" disabled>Refuel</button>
          </div>
        </div>


        <div class="stat">
          <%
            cargo_current = get_in(@ship, ~w(cargo units))
            cargo_capacity = get_in(@ship, ~w(cargo capacity))
            cargo_percent = trunc(Float.ceil(cargo_current / cargo_capacity * 100))
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
      </section>

      <div role="tablist" class="tabs tabs-bordered mb-8">
        <a role="tab" class="tab tab-active">Current Location</a>
        <a role="tab" class="tab">Navigate</a>
        <a role="tab" class="tab">Cargo</a>
        <a role="tab" class="tab">Subsystems</a>
        <a role="tab" class="tab">Registration</a>
      </div>

      <section class="grow flex flex-col">
        <div class="bg-base-200 p-4 rounded grow">
          <header class="mb-8">
            <div class="text-2xl font-bold"><%= get_in(@ship, ~w(nav route destination symbol)) %></div>
            <div class="text-xl text-neutral-500"><%= get_in(@ship, ~w(nav route destination type)) %></div>
          </header>
          <.async_result :let={waypoint} assign={@waypoint}>
            <:loading><span class="loading loading-ring loading-lg"></span></:loading>
            <:failed :let={_failure}>There was an error loading the waypoint.</:failed>


            <div class="flex justify-start gap-8">
              <section class="basis-44">
                <div class="font-bold text-lg">Traits</div>
                <ul class="list-disc ml-4">
                <%= for trait <- waypoint["traits"] do %>
                  <li>
                    <span
                      class={["tooltip"] ++ badge_class_for_trait(trait["symbol"])}
                      data-tip={trait["description"]}
                    >
                      <%= trait["name"] %>
                    </span>
                  </li>
                <% end %>
                </ul>
              </section>

              <section class="basis-44">
                <div class="font-bold text-lg">Modifiers</div>

                <%= if Enum.empty?(waypoint["modifiers"]) do %>
                  <p>No modifiers</p>
                <% else %>
                  <ul class="list-disc ml-4">
                    <%= for trait <- waypoint["modifiers"] do %>
                      <li><%= trait["name"] %></li>
                    <% end %>
                  </ul>
                <% end %>
              </section>

              <section class="basis-44">
                <div class="mb-4">
                  <div class="font-bold text-lg">Orbits</div>

                  <%= if is_nil(waypoint["orbits"]) do %>
                    <p>This body does not orbit anything.</p>
                  <% else %>
                    <%= waypoint["orbits"] %>
                  <% end %>
                </div>

                <div class="font-bold text-lg">Orbitals</div>

                <%= if Enum.empty?(waypoint["orbitals"]) do %>
                  <p>None</p>
                <% else %>
                  <ul class="list-disc ml-4">
                    <%= for orbital <- waypoint["orbitals"] do %>
                      <li><%= orbital["symbol"] %></li>
                    <% end %>
                  </ul>
                <% end %>
              </section>
            </div>
          </.async_result>
        </div>
      </section>
    </section>
    """
  end

  def mount(socket) do
    {:ok, assign(socket, %{
      tab: :waypoint
    })}
  end

  def update(assigns, socket) do
    socket = assign(socket, assigns)
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

  defp badge_class_for_trait("MARKETPLACE"), do: ["badge badge-accent"]
  defp badge_class_for_trait(_trait_symbol), do: ["badge badge-neutral"]

end
