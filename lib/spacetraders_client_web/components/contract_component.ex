defmodule SpacetradersClientWeb.ContractComponent do
  use SpacetradersClientWeb, :html

  attr :contract, :map, required: true

  def view(assigns) do
    ~H"""
    <div class="text-xl font-bold mb-8">{@contract["type"]} for {@contract["factionSymbol"]}</div>

    <dl>
      <dt class="font-bold">Deadline</dt>
      <dd class="ml-6 mb-2">{@contract["terms"]["deadline"]}</dd>
      <dt class="font-bold">Payment on accept</dt>
      <dd class="ml-6 mb-2">{@contract["terms"]["payment"]["onAccepted"]}</dd>
      <dt class="font-bold">Payment on fulfillment</dt>
      <dd class="ml-6 mb-2">{@contract["terms"]["payment"]["onFulfilled"]}</dd>
      <dt class="font-bold">Items to deliver</dt>
      <dd class="ml-6 mb-2">
        <ul class="list-disc">
          <%= for item <- @contract["terms"]["deliver"] do %>
            <li>
              {item["unitsRequired"]} units of {item["tradeSymbol"]} to
              <.link
                class="link"
                patch={
                  ~p"/game/systems/#{waypoint_system(item["destinationSymbol"])}/waypoints/#{item["destinationSymbol"]}"
                }
              >
                {item["destinationSymbol"]}
              </.link>
            </li>
          <% end %>
        </ul>
      </dd>
    </dl>
    """
  end

  defp waypoint_system(waypoint_symbol) do
    [sector, system, _waypoint] = String.split(waypoint_symbol, "-", parts: 3)

    sector <> "-" <> system
  end
end
