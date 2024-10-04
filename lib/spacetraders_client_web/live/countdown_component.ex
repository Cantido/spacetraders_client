defmodule SpacetradersClientWeb.CountdownComponent do
  use SpacetradersClientWeb, :live_component

  attr :expiration, DateTime, required: true
  attr :class, :string, default: nil
  attr :rest, :global

  def render(assigns) do
    ~H"""
    <% diff = trunc(DateTime.diff(DateTime.utc_now(), @expiration)) %>
    <div class={["countdown font-mono text-4xl", @class]} {@rest}>
      <span style={"--value:#{diff};"}></span>
    </div>
    """
  end
end
