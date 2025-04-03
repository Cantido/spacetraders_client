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
          {name}
        </a>
      <% end %>
    </div>
    """
  end

  attr :name, :string, required: true
  attr :class, :string, default: nil
  attr :rest, :global

  slot :tab do
    attr :label, :string, required: true
    attr :active, :boolean
    attr :class, :string
  end

  def radio_tablist(assigns) do
    ~H"""
    <div role="tablist" {@rest} class={["tabs", @class]}>
      <%= for tab <- @tab do %>
        <input
          type="radio"
          class="tab"
          name={@name}
          aria-label={tab.label}
          checked={Map.get(tab, :active, false)}
        />
        <div class={["tab-content", Map.get(tab, :class)]}>
          {render_slot(tab)}
        </div>
      <% end %>
    </div>
    """
  end
end
