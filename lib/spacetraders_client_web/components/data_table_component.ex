defmodule SpacetradersClientWeb.DataTableComponent do
  use SpacetradersClientWeb, :live_component

  attr :rows, :list, default: []
  attr :class, :string, default: nil
  attr :initial_sort_key, :atom, required: true
  attr :initial_sort_direction, :atom, required: true, values: [:asc, :desc]

  slot :column, required: true do
    attr :label, :string, required: true
    attr :key, :atom, required: true
    attr :class, :string
  end

  slot :footer



  def render(assigns) do
    ~H"""
    <table class={["table", @class]}>
      <thead>
        <%= for col <- @column do %>
          <th
            class={[col[:class]]}
          >
            <a
              class="cursor-pointer"
              phx-click="header-clicked"
              phx-value-key={col.key}
              phx-target={@myself}
            >
              <%= col.label %>

              <%= cond do %>
                <% @sort_key == col.key && @sort_direction == :asc -> %>
                  <.icon name="hero-chevron-up" />
                <% @sort_key == col.key && @sort_direction == :desc -> %>
                  <.icon name="hero-chevron-down" />
                <% true -> %>
                  <.icon name="hero-chevron-up-down" />
              <% end %>
            </a>
          </th>
        <% end %>
      </thead>
      <tbody>
        <% sort_column = Enum.find(@column, fn col -> to_string(col.key) == to_string(@sort_key) end) %>
        <%= for row <- Enum.sort_by(@rows, fn row -> Map.get(row, @sort_key) end, sorter(@sort_direction, Map.get(sort_column, :sorter))) do %>
          <tr>
            <%= for col <- @column do %>
              <td
                class={[col[:class]]}
              >
                <%= render_slot(col, row) %>
              </td>
            <% end %>
          </tr>
        <% end %>
      </tbody>
      <tfoot>
        <%= render_slot @footer %>
      </tfoot>
    </table>
    """
  end

  def sorter(sort_direction, nil), do: sort_direction
  def sorter(sort_direction, sort_module), do: {sort_direction, sort_module}

  def mount(socket) do
    socket =
      assign(socket, %{
        sort_direction: :asc,
        sort_module: nil,
        sort_key: nil
      })

    {:ok, socket}
  end


  def update(assigns, socket) do
    socket = assign(socket, assigns)

    socket =
      if sort = assigns[:initial_sort_direction] do
        assign(socket, :sort_direction, sort)
      else
        socket
      end

    socket =
      if key = assigns[:initial_sort_key] do
        assign(socket, :sort_key, key)
      else
        socket
      end

    {:ok, socket}
  end

  def handle_event("header-clicked", %{"key" => key}, socket) do
    socket = assign(socket, :sort_key, key)

    {:noreply, socket}
  end
end
