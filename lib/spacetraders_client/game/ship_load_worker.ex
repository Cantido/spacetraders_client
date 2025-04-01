defmodule SpacetradersClient.Game.ShipLoadWorker do
  use Oban.Worker,
    queue: :api

  alias SpacetradersClient.Client
  alias SpacetradersClient.Game

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"ship_symbol" => ship_symbol, "token" => token}}) do
    client = Client.new(token)

    Game.load_ship!(client, ship_symbol)

    :ok
  end
end
