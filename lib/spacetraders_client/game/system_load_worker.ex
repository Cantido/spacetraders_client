defmodule SpacetradersClient.Game.SystemLoadWorker do
  use Oban.Worker,
    queue: :api,
    unique: [
      period: :infinity,
      keys: [:page],
      fields: [:worker, :args]
    ]

  alias SpacetradersClient.Client
  alias SpacetradersClient.Game.Agent
  alias SpacetradersClient.Game.System
  alias SpacetradersClient.Systems
  alias SpacetradersClient.Repo

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"page" => page}}) do
    if agent = Repo.one(Agent) do
      client = Client.new(agent.token)

      {:ok, %{body: body, status: 200}} = Systems.list_systems(client, page: page)

      body["data"]
      |> Enum.each(fn system ->
        if is_nil(Repo.get_by(System, symbol: system["symbol"])) do
          %System{}
          |> System.changeset(system)
          |> Repo.insert!(on_conflict: :nothing)
        end
      end)

      Phoenix.PubSub.broadcast(SpacetradersClient.PubSub, "galaxy", :galaxy_updated)

      if Repo.aggregate(System, :count) < body["meta"]["total"] do
        %{page: page + 1}
        |> new(priority: 9)
        |> Oban.insert!()
      end

      :ok
    else
      {:snooze, 60}
    end
  end
end
