defmodule SpacetradersClientWeb.GameLoader do
  use Phoenix.VerifiedRoutes,
    endpoint: SpacetradersClientWeb.Endpoint,
    router: SpacetradersClientWeb.Router

  alias Phoenix.Component
  alias Phoenix.LiveView.AsyncResult
  alias Phoenix.LiveView
  alias SpacetradersClient.Client
  alias SpacetradersClient.Agents
  alias SpacetradersClient.Game.Agent
  alias SpacetradersClient.Repo

  import Phoenix.LiveView

  def on_mount(:agent, _params, %{"token" => token}, socket) do
    client = Client.new(token)

    case Agents.my_agent(client) do
      {:ok, %{status: 401}} ->
        {:halt, redirect(socket, to: ~p"/login")}

      {:ok, %{status: 200, body: agent_body}} ->
        agent =
          if agent = Repo.get(Agent, agent_body["data"]["symbol"]) do
            agent
          else
            %Agent{token: token}
          end
          |> Agent.changeset(agent_body["data"])
          |> Repo.insert_or_update!(on_conflict: {:replace, [:credits]})

        socket =
          socket
          |> Component.assign(%{
            token: token,
            client: client,
            agent: AsyncResult.ok(agent),
            agent_symbol: agent.symbol,
            ledger: AsyncResult.loading()
          })

        {:cont, socket}
    end
  end

  def mount(:agent, _params, _token, socket) do
    {:halt, redirect(socket, to: ~p"/login")}
  end
end
