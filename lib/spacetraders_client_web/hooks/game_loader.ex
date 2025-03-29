defmodule SpacetradersClientWeb.GameLoader do
  use Phoenix.VerifiedRoutes,
    endpoint: SpacetradersClientWeb.Endpoint,
    router: SpacetradersClientWeb.Router

  alias Phoenix.Component
  alias Phoenix.LiveView.AsyncResult
  alias Phoenix.LiveView
  alias SpacetradersClient.Client
  alias SpacetradersClient.Agents
  alias SpacetradersClient.Fleet
  alias SpacetradersClient.Systems
  alias SpacetradersClient.Repo

  alias SpacetradersClient.Game.Agent
  alias SpacetradersClient.Game.System
  alias SpacetradersClient.Game.Waypoint
  alias SpacetradersClient.Game.Ship
  alias SpacetradersClient.Game.Market
  alias SpacetradersClient.Game.Item
  alias SpacetradersClient.Game.Shipyard

  import Phoenix.LiveView

  import Ecto.Query

  def on_mount(:agent, _params, %{"token" => token}, socket) do
    client = Client.new(token)

    {:ok, %{status: 200, body: agent_body}} = Agents.my_agent(client)

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

    # |> LiveView.assign_async(:ledger, fn ->
    #   case SpacetradersClient.LedgerServer.ledger(agent_symbol) do
    #     {:ok, ledger} ->
    #       {:ok, %{ledger: ledger}}

    #     {:error, reason} ->
    #       dbg(reason)
    #       {:error, reason}
    #   end
    # end)

    {:cont, socket}
  end

  def mount(:agent, _params, _token, socket) do
    {:halt, redirect(socket, to: ~p"/login")}
  end

  def load_user_async(client, progress_report_pid) do
    Task.Supervisor.start_child(
      SpacetradersClient.TaskSupervisor,
      fn ->
        {:ok, %{status: 200, body: agent_body}} = Agents.my_agent(client)

        agent =
          %Agent{}
          |> Agent.changeset(agent_body["data"])
          |> Repo.insert!(on_conflict: {:replace, [:credits]})

        send(progress_report_pid, {:load_progress, :agent, 1, 1, agent})

        Stream.iterate(1, &(&1 + 1))
        |> Stream.map(fn page ->
          Fleet.list_ships(client, page: page)
        end)
        |> Stream.map(fn page ->
          {:ok, %{body: body, status: 200}} = page

          Enum.map(body["data"], fn ship ->
            ship["nav"]["systemSymbol"]
          end)
          |> Enum.uniq()
          |> Enum.each(fn system_symbol ->
            if is_nil(Repo.get(System, system_symbol)) do
              {:ok, %{body: body, status: 200}} = Systems.get_system(client, system_symbol)

              system =
                %System{}
                |> System.changeset(body["data"])
                |> Repo.insert!(on_conflict: :nothing)

              Stream.iterate(1, &(&1 + 1))
              |> Stream.map(fn page ->
                Systems.list_waypoints(client, system_symbol, page: page)
              end)
              |> Stream.map(fn page ->
                {:ok, %{body: body, status: 200}} = page

                body
              end)
              |> Enum.reduce_while([], fn page, waypoints ->
                {:ok, new_waypoints} =
                  Repo.transaction(fn ->
                    Enum.map(page["data"], fn waypoint ->
                      Ecto.build_assoc(system, :waypoints)
                      |> Waypoint.changeset(waypoint)
                      |> Repo.insert!(on_conflict: :replace_all)
                    end)
                  end)

                acc_waypoints = waypoints ++ new_waypoints

                if Enum.count(acc_waypoints) < page["meta"]["total"] do
                  {:cont, acc_waypoints}
                else
                  {:halt, acc_waypoints}
                end
              end)

              Enum.each(body["data"]["waypoints"], fn wp ->
                from(w in Waypoint, where: [symbol: ^wp["symbol"]])
                |> Repo.update_all(set: [orbits_waypoint_symbol: wp["orbits"]])
              end)

              from(w in Waypoint,
                join: t in assoc(w, :traits),
                where: [system_symbol: ^system_symbol],
                where: t.symbol == "MARKETPLACE",
                select: w.symbol
              )
              |> Repo.all()
              |> Enum.map(fn waypoint_symbol ->
                {:ok, %{body: body, status: 200}} =
                  Systems.get_market(client, system_symbol, waypoint_symbol)

                body["data"]["exports"]
                |> Enum.concat(body["data"]["imports"])
                |> Enum.concat(body["data"]["exchange"])
                |> Enum.each(fn e ->
                  %Item{}
                  |> Item.changeset(e)
                  |> Repo.insert!(on_conflict: :nothing)
                end)

                %Market{symbol: waypoint_symbol}
                |> Market.changeset(body["data"])
                |> Repo.insert!()
              end)

              from(w in Waypoint,
                join: t in assoc(w, :traits),
                where: [system_symbol: ^system_symbol],
                where: t.symbol == "SHIPYARD",
                select: w.symbol
              )
              |> Repo.all()
              |> Enum.map(fn waypoint_symbol ->
                {:ok, %{body: body, status: 200}} =
                  Systems.get_shipyard(client, system_symbol, waypoint_symbol)

                %Shipyard{symbol: waypoint_symbol}
                |> Shipyard.changeset(body["data"])
                |> Repo.insert!()
              end)
            end
          end)

          page
        end)
        |> Enum.reduce_while([], fn page, ships ->
          case page do
            {:ok, %{body: body, status: 200}} ->
              {:ok, new_ships} =
                Repo.transaction(fn ->
                  Enum.map(body["data"], fn ship ->
                    Ecto.build_assoc(agent, :ships)
                    |> Ship.changeset(ship)
                    |> Repo.insert!(on_conflict: :replace_all)
                  end)
                end)

              ship_count =
                Ecto.assoc(agent, :ships)
                |> Repo.aggregate(:count)

              acc_ships = ships ++ new_ships

              send(
                progress_report_pid,
                {:load_progress, :fleet, Enum.count(acc_ships), body["meta"]["total"], acc_ships}
              )

              if ship_count < Map.fetch!(body["meta"], "total") do
                {:cont, acc_ships}
              else
                {:halt, {:ok, acc_ships}}
              end

            {:ok, result} ->
              {:error, result}

            {:error, reason} ->
              {:error, reason}
          end
        end)
      end
    )
  end
end
