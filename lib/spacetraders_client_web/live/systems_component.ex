defmodule SpacetradersClientWeb.SystemsComponent do
  use SpacetradersClientWeb, :live_component

  attr :system, :map, required: true
  attr :agent, :map, required: true
  attr :fleet, :list

  def render(assigns) do
    ~H"""
    <section class="h-full w-full">
      <h3 class="px-5 py-2 bg-neutral font-bold text-xl">
        System
      </h3>

      <div class="m-8">
        <dl>
          <dt class="font-bold">Sector</dt>
          <dd class="ml-6 mb-2 font-mono"><%= @system["sectorSymbol"] %></dd>
          <dt class="font-bold">Type</dt>
          <dd class="ml-6 mb-2"><%= @system["type"] %></dd>
          <dt class="font-bold">Factions</dt>
          <dd class="ml-6 mb-2">
            <%= if Enum.any?(@system["factions"]) do %>
              <ul>
              <%= for faction <- @system["factions"] do %>
                <li><%= faction["symbol"] %></li>
              <% end %>
              </ul>
            <% else %>
              None
            <% end %>
          </dd>
        </dl>
      </div>
    </section>
    """
  end
end
