defmodule SpacetradersClientWeb.WaypointMarketComponent do
  use SpacetradersClientWeb, :html

  attr :system_symbol, :string, required: true
  attr :waypoint_symbol, :string, required: true
  attr :market, :map, required: true

  def table(assigns) do
    ~H"""
    <div class="flex-1 grow">
      <%!-- <%= if items = @market["tradeGoods"] do %> --%>
        <%!-- <.item_table items={items} /> --%>
      <%!-- <% else %> --%>
        <.imports_exports market={@market} system_symbol={@system_symbol} waypoint_symbol={@waypoint_symbol} />
      <%!-- <% end %> --%>
    </div>
    """
  end

  def imports_exports(assigns) do
    ~H"""
    <div class="flex">
      <div class="flex-1">
        <div class="text-center font-bold mb-8">Imports</div>

        <%= if Enum.any?(@market.imports) do %>
          <.item_list items={@market.imports} />
        <% else %>
          <div class="text-center mt-16">No imports</div>
        <% end %>
      </div>
      <div class="divider divider-horizontal"></div>
      <div class="flex-1">
        <div class="text-center font-bold mb-8">Exchanges</div>

        <%= if Enum.any?(@market.exchanges) do %>
          <.item_list items={@market.exchanges} />
        <% else %>
          <div class="text-center mt-16">No exchanges</div>
        <% end %>
      </div>
      <div class="divider divider-horizontal"></div>
      <div class="flex-1">
        <div class="text-center font-bold mb-8">Exports</div>

        <%= if Enum.any?(@market.exports) do %>
          <.item_list items={@market.exports} />
        <% else %>
          <div class="text-center mt-16">No exports</div>
        <% end %>
      </div>
    </div>
    """
  end

  defp item_list(assigns) do
    ~H"""
    <table class="table table-zebra border border-2 border-neutral">
      <tbody>
      <%= for item <- @items do %>
        <tr>
          <td><%= item.item_symbol %></td>
        </tr>
      <% end %>
      </tbody>
    </table>
    """
  end

  def item_table(assigns) do
    ~H"""
      <table class="table table-zebra table-pin-rows table-sm">
        <thead class="border-b-4 border-neutral">
          <tr>
            <th>Item</th>
            <th class="text-right">Volume</th>
            <th class="text-right">Offer price</th>
            <th class="text-right">Bid price</th>
            <th class="w-40">Purchase</th>
          </tr>
        </thead>
        <tbody>
        <%= for item <- @items do %>
          <tr>
            <td><%= item.item_symbol %></td>
            <td class="text-right"><%= item.trade_volume %></td>
            <td class="text-right"><%= item.purchase_price %></td>
            <td class="text-right"><%= item.sell_price %></td>
            <td class="text-right flex flex-row">
              <div class="join">
                <button class="btn btn-xs btn-error join-item">Buy</button>
                <input type="number" value="0" class="join-item input input-xs w-full max-w-xs" />
              </div>
            </td>
          </tr>
        <% end %>
        </tbody>
      </table>
    """
  end
end
