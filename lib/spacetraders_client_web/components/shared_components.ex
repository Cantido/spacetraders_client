defmodule SpacetradersClientWeb.SharedComponents do
  use Phoenix.Component

  attr :tabs, :list, required: true, examples: [[{"tab-1", "Tab 1"}]]
  attr :active_tab_id, :string, required: true
  attr :target, :any, required: true
  attr :rest, :global

  def tablist(assigns) do
    ~H"""
    <div role="tablist" {@rest} class="tabs tabs-bordered mb-12 w-full">
      <%= for {id, name} <- @tabs do %>
        <a
          role="tab"
          class={if to_string(@active_tab_id) == to_string(id), do: ["tab tab-active"], else: ["tab"]}
          phx-click="select-tab"
          phx-value-tab={id}
          phx-target={@target}
        >
          <%= name %>
        </a>
      <% end %>
    </div>
    """
  end
end
