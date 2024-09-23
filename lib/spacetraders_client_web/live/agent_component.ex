defmodule SpacetradersClientWeb.AgentComponent do
  use SpacetradersClientWeb, :live_component

  def render(assigns) do
    ~H"""
    <section class="p-8 h-full w-full">
      <header class="mb-4">
        <h2 class="text-neutral-500">Agent</h2>
        <h1 class="text-2xl"><%= @agent["symbol"] %></h1>
      </header>

      <dl>
        <dt class="font-bold">Account ID</dt>
        <dd class="ml-6 mb-2 font-mono"><%= @agent["accountId"] %></dd>
        <dt class="font-bold">Headquarters</dt>
        <dd class="ml-6 mb-2 font-mono"><%= @agent["headquarters"] %></dd>
        <dt class="font-bold">Starting Faction</dt>
        <dd class="ml-6 mb-2 font-mono"><%= @agent["startingFaction"] %></dd>
      </dl>
    </section>
    """
  end
end
