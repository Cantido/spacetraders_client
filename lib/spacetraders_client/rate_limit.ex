defmodule SpacetradersClient.RateLimit do
  @behaviour Tesla.Middleware

  require Logger

  @impl true
  def call(env, next, options) do
    case Hammer.check_rate("SpaceTraders API (static pool)", :timer.seconds(1), 2) do
      {:allow, _count} ->
        Tesla.run(env, next)

      {:deny, _limit} ->
        Process.sleep(250)
        call(env, next, options)
    end
  end
end
