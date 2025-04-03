defmodule SpacetradersClientWeb.ShipCargoComponent do
  use SpacetradersClientWeb, :html

  attr :ship, :map, required: true

  def cargo(assigns) do
    ~H"""
    <table class="table table-zebra">
      <thead>
        <tr>
          <td>Name</td>
          <td>Units</td>
          <td>Actions</td>
        </tr>
      </thead>
      <tbody>
        <%= for item <- @ship.cargo_items do %>
          <tr>
            <td><%= item.item.name %></td>
            <td><%= item.units %></td>
            <td>
              <button
                class="btn btn-xs btn-error"
                data-confirm={"Are you sure you want to jettison #{item.units} unit(s) of #{item.item.name}?"}
                phx-click="jettison-cargo"
                phx-value-ship-symbol={@ship.symbol}
                phx-value-item-symbol={item.item.symbol}
                phx-value-units={item.units}
              >
                Jettison
              </button>
            </td>
          </tr>
        <% end %>
      </tbody>
    </table>
    """
  end
end
