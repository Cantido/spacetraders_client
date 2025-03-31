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
          %Agent{}
          |> Agent.changeset(agent_body["data"])
          |> Repo.insert!(on_conflict: {:replace, [:credits]})

        socket =
          socket
          |> Component.assign(%{
            token: token,
            client: client,
            agent: AsyncResult.ok(agent),
            agent_symbol: agent.symbol,
            # agent_automaton: AsyncResult.loading(),
            ledger: AsyncResult.loading()
          })
          |> LiveView.assign_async(:agent_automaton, fn ->
            case SpacetradersClient.AutomationServer.automaton(agent.symbol) do
              {:ok, agent_automaton} ->
                {:ok, %{agent_automaton: agent_automaton}}

              {:error, _reason} ->
                {:ok, %{agent_automaton: nil}}
            end
          end)

        {:cont, socket}
    end
  end

  def mount(:agent, _params, _token, socket) do
    {:halt, redirect(socket, to: ~p"/login")}
  end
end
