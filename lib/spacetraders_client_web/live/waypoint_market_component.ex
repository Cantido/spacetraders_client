defmodule SpacetradersClientWeb.WaypointMarketComponent do
  use SpacetradersClientWeb, :live_component

  alias SpacetradersClient.Systems

  attr :client, Tesla.Client, required: true
  attr :system_symbol, :string, required: true
  attr :waypoint_symbol, :string, required: true
  attr :market, :map, required: true

  def render(assigns) do
    ~H"""
    <div class="flex-1 grow border border-2 border-neutral overflow-y-auto">
      <%= if items = @market["tradeGoods"] do %>
        <.item_table items={items} />
      <% else %>
        <div class="flex">
          <div class="flex-1">
            <div class="text-center font-bold mb-8">Imports</div>

            <%= if Enum.any?(@market["imports"]) do %>
              <.item_table items={@market["imports"]} />
            <% else %>
              <div class="text-center mt-16">No imports</div>
            <% end %>
          </div>
          <div class="divider divider-horizontal"></div>
          <div class="flex-1">
            <div class="text-center font-bold mb-8">Exchanges</div>

            <%= if Enum.any?(@market["exchange"]) do %>
              <.item_list items={@market["exchange"]} />
            <% else %>
              <div class="text-center mt-16">No exchanges</div>
            <% end %>
          </div>
          <div class="divider divider-horizontal"></div>
          <div class="flex-1">
            <div class="text-center font-bold">Exports</div>

            <%= if Enum.any?(@market["exports"]) do %>
              <.item_table items={@market["exports"]} />
            <% else %>
              <div class="text-center mt-16">No exports</div>
            <% end %>
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  defp item_list(assigns) do
    ~H"""
    <table class="table table-zebra border border-2 border-neutral">
      <tbody>
      <%= for item <- @items do %>
        <tr>
          <td><%= item["name"] %></td>
        </tr>
      <% end %>
      </tbody>
    </table>
    """
  end

  defp item_table(assigns) do
    ~H"""
      <table class="table table-zebra table-pin-rows">
        <thead class="border-b-4 border-neutral">
          <tr>
            <th>Item</th>
            <th>Supply</th>
            <th>Activity</th>
            <th>Volume</th>
            <th>Buy</th>
            <th>Sell</th>
          </tr>
        </thead>
        <tbody>
        <%= for item <- @items do %>
          <tr>
            <td><%= item["symbol"] %></td>
            <td><%= item["supply"] %></td>
            <td><%= item["activity"] %></td>
            <td class="text-right"><%= item["tradeVolume"] %></td>
            <td class="text-right"><%= item["purchasePrice"] %></td>
            <td class="text-right"><%= item["sellPrice"] %></td>
          </tr>
        <% end %>
        </tbody>
      </table>
    """
  end
end
