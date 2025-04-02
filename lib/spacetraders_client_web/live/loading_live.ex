defmodule SpacetradersClientWeb.LoadingLive do
  use SpacetradersClientWeb, :live_view

  alias Phoenix.PubSub

  require Logger

  @pubsub SpacetradersClient.PubSub

  def render(assigns) do
    ~H"""
    <div class="hero">
      <div class="hero-content flex-col">
        <div class="text-3xl font-bold">
          Loading your stuff!
        </div>

        <div class="loading loading-dots loading-xl"></div>

        <div class="grid grid-cols-3 items-center gap-2">
          <div class="justify-self-end">Agent</div>

          <progress :if={!@agent.ok?} class="progress w-56"></progress>
          <progress :if={@agent.ok?} class="progress progress-success w-56" value="1" max="1"></progress>

          <div class="text-base-content/50 text-xs">
            <%= if @agent.ok? do %>
              1 of 1
            <% else %>
              0 of 1
            <% end %>
          </div>
          <div class="justify-self-end">Fleet</div>

          <.loading_progress_bar loading_count={@fleet_total} loaded_count={@fleet_loaded} />

          <div class="text-base-content/50 text-xs">
            <%= if @fleet_total == 0 do %>
              discovering&hellip;
            <% else %>
              {@fleet_loaded} of {@fleet_total}
            <% end %>
          </div>

          <div class="justify-self-end">Waypoints</div>

          <%
            {system_loaded_count, system_loading_count} = load_progress(@progress_keys, :system_waypoints)
          %>

          <.loading_progress_bar
            loaded_count={system_loaded_count}
            loading_count={system_loading_count}
          />

          <div class="text-base-content/50 text-xs">
            <%= if system_loading_count == 0 do %>
              discovering&hellip;
            <% else %>
              {system_loaded_count} of {system_loading_count}
            <% end %>
          </div>
          <div class="justify-self-end">Markets</div>
          <%
            market_loading_count = Enum.count(Map.get(@loading_keys, :market, []))
            market_loaded_count = Enum.count(Map.get(@loaded_keys, :market, []))
          %>

          <.loading_progress_bar
            loading_count={market_loading_count}
            loaded_count={market_loaded_count}
          />
          <div class="text-base-content/50 text-xs">
            <%= if market_loading_count == 0 do %>
              discovering&hellip;
            <% else %>
              {market_loaded_count} of {market_loading_count}
            <% end %>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp loading_progress_bar(assigns) do
    ~H"""
    <%= cond do %>
      <% @loading_count == 0 -> %>
        <progress class="progress w-56"></progress>
      <% @loaded_count < @loading_count -> %>
        <progress class="progress w-56" value={@loaded_count} max={@loading_count}></progress>
      <% true -> %>
        <progress class="progress progress-success w-56" value={@loaded_count} max={@loading_count}>
        </progress>
    <% end %>
    """
  end

  def load_progress(progresses, progress_key) do
    progresses =
      Map.get(progresses, progress_key, %{})
      |> Map.values()

    loading = Enum.sum_by(progresses, fn {loading, _total} -> loading end)
    total = Enum.sum_by(progresses, fn {_loading, total} -> total end)
    {loading, total}
  end

  on_mount {SpacetradersClientWeb.GameLoader, :agent}

  def mount(_params, _session, socket) do
    SpacetradersClient.Game.AgentLoadWorker.new(%{})
    |> Oban.insert!()

    PubSub.subscribe(@pubsub, "agent:#{socket.assigns.agent_symbol}")

    socket =
      socket
      |> assign(%{
        loading_keys: %{},
        loaded_keys: %{},
        progress_keys: %{},
        fleet_loaded: 0,
        fleet_total: 0
      })

    {:ok, socket, layout: false}
  end

  def handle_info({:data_loading, entity_type, entity_key}, socket) do
    socket =
      update(socket, :loading_keys, fn loading_keys ->
        update_in(loading_keys, [Access.key(entity_type, MapSet.new())], fn keys ->
          MapSet.put(keys, entity_key)
        end)
      end)

    {:noreply, socket}
  end

  def handle_info({:data_loaded, entity_type, entity_key}, socket) do
    socket =
      update(socket, :loaded_keys, fn loaded_keys ->
        update_in(loaded_keys, [Access.key(entity_type, MapSet.new())], fn keys ->
          MapSet.put(keys, entity_key)
        end)
      end)

    {:noreply, socket}
  end

  def handle_info({:data_loading_progress, entity_type, entity_key, progress, total}, socket) do
    socket =
      update(socket, :progress_keys, fn progress_keys ->
        put_in(progress_keys, [Access.key(entity_type, %{}), entity_key], {progress, total})
      end)

    {:noreply, socket}
  end

  def handle_info({:data_loaded, :fleet, loaded, total}, socket) do
    socket =
      assign(socket, %{
        fleet_loaded: loaded,
        fleet_total: total
      })

    {:noreply, socket}
  end

  def handle_info(msg, socket) do
    Logger.warning("Received unknown info message: #{inspect(msg)}")
    {:noreply, socket}
  end
end
