defmodule SpacetradersClientWeb.GalaxyLive do
  use SpacetradersClientWeb, :live_view

  alias SpacetradersClient.Game.System
  alias SpacetradersClient.Repo

  import Ecto.Query, except: [update: 3]

  def render(assigns) do
    ~H"""
    hi, there are {@system_count} systems in {@constellation_count} constellations right now
    """
  end

  on_mount {SpacetradersClientWeb.GameLoader, :agent}

  def mount(_params, _session, socket) do
    Phoenix.PubSub.subscribe(SpacetradersClient.PubSub, "galaxy")
    system_count = Repo.aggregate(System, :count)

    constellation_count =
      from(s in System,
        select: s.constellation,
        distinct: true
      )
      |> Repo.aggregate(:count)

    socket =
      socket
      |> assign(%{
        system_count: system_count,
        constellation_count: constellation_count
      })

    {:ok, assign(socket, :app_section, :galaxy)}
  end

  def handle_info(:galaxy_updated, socket) do
    system_count = Repo.aggregate(System, :count)

    constellation_count =
      from(s in System,
        select: s.constellation,
        distinct: true
      )
      |> Repo.aggregate(:count)

    socket =
      socket
      |> assign(%{
        system_count: system_count,
        constellation_count: constellation_count
      })

    {:noreply, socket}
  end
end
