defmodule SpacetradersClientWeb.WaypointInfoComponent do
  use SpacetradersClientWeb, :html

  def traits(assigns) do
    ~H"""
    <ul class="flex flex-wrap gap-1">
    <%= for trait <- @waypoint.traits do %>
      <li>
        <span
          class={["tooltip tooltip-bottom w-max"] ++ badge_class_for_trait(trait.symbol)}
          data-tip={trait.description}
        >
          <%= trait.name %>
        </span>
      </li>
    <% end %>
    </ul>
    """
  end

  defp badge_class_for_trait("MARKETPLACE"), do: ["badge badge-primary"]
  defp badge_class_for_trait("SHIPYARD"), do: ["badge badge-primary"]
  defp badge_class_for_trait(_trait_symbol), do: ["badge badge-neutral"]
end
