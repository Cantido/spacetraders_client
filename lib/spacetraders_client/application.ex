defmodule SpacetradersClient.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    :ok = SpacetradersClient.ObanLogger.attach_logger()

    children = [
      SpacetradersClientWeb.Telemetry,
      {DNSCluster,
       query: Application.get_env(:spacetraders_client, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: SpacetradersClient.PubSub},
      SpacetradersClient.Repo,
      {SpacetradersClient.Cache, []},
      {Task.Supervisor, name: SpacetradersClient.TaskSupervisor},
      Cldr.Currency,
      # Start the Finch HTTP client for sending emails
      {Finch, name: SpacetradersClient.Finch},
      # Start a worker by calling: SpacetradersClient.Worker.start_link(arg)
      # {SpacetradersClient.Worker, arg},
      SpacetradersClient.AutomationServer,
      {Oban, Application.fetch_env!(:spacetraders_client, Oban)},
      # Start to serve requests, typically the last entry
      SpacetradersClientWeb.Endpoint,

    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: SpacetradersClient.Supervisor]
    result = Supervisor.start_link(children, opts)

    case result do
      {:ok, _} ->
        {:ok, _} = Cldr.Currency.new(:XST, name: "SpaceTraders credits", digits: 0)

        %{page: 1}
        |> SpacetradersClient.Game.SystemLoadWorker.new(priority: 9)
        |> Oban.insert!()

      _ ->
        :noop
    end

    result
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    SpacetradersClientWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
