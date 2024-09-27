defmodule SpacetradersClientWeb.WaypointInfoComponent do
  use SpacetradersClientWeb, :html

  def traits(assigns) do
    ~H"""
    <div class="font-bold text-lg">Traits</div>
    <ul class="list-disc ml-4">
    <%= for trait <- @waypoint["traits"] do %>
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
    """
  end

  def modifiers(assigns) do
    ~H"""
    <div class="font-bold text-lg">Modifiers</div>

    <%= if Enum.empty?(@waypoint["modifiers"]) do %>
      <p>No modifiers</p>
    <% else %>
      <ul class="list-disc ml-4">
        <%= for trait <- @waypoint["modifiers"] do %>
          <li><%= trait["name"] %></li>
        <% end %>
      </ul>
    <% end %>
    """
  end

  defp badge_class_for_trait("MARKETPLACE"), do: ["badge badge-accent"]
  defp badge_class_for_trait("SHIPYARD"), do: ["badge badge-accent"]
  defp badge_class_for_trait(_trait_symbol), do: ["badge badge-neutral"]
end
