defmodule SpacetradersClient.Game.Waypoint do
  use Ecto.Schema

  alias SpacetradersClient.Game.System
  alias SpacetradersClient.Game.WaypointModifier
  alias SpacetradersClient.Game.WaypointTrait

  import Ecto.Changeset

  @timestamps_opts [type: :utc_datetime_usec]

  @derive {Inspect, only: [:symbol]}
  @derive {Jason.Encoder, except: [:__meta__, :__struct__, :system, :orbitals, :orbits_waypoint]}

  schema "waypoints" do
    field :symbol, :string
    belongs_to :system, System

    field :type, :string
    field :x_coordinate, :integer
    field :y_coordinate, :integer
    field :under_construction, :boolean

    belongs_to :orbits_waypoint, __MODULE__

    has_many :orbitals, __MODULE__,
      preload_order: [asc: :symbol],
      foreign_key: :orbits_waypoint_id

    has_many :modifiers, WaypointModifier, on_replace: :delete_if_exists

    has_many :traits, WaypointTrait, on_replace: :delete_if_exists

    timestamps()
  end

  def changeset(model, params) do
    model
    |> cast(params, [:symbol, :type])
    |> change(%{
      x_coordinate: params["x"],
      y_coordinate: params["y"]
    })
    |> unique_constraint(:symbol)
    |> cast_assoc(:modifiers)
    |> cast_assoc(:traits)
  end

  def add_orbits(model, params) do
    model
    |> put_assoc(:orbits, %__MODULE__{
      symbol: params["orbits"]
    })
    |> put_assoc(
      :orbitals,
      Enum.map(params["orbitals"], fn o ->
        %__MODULE__{
          symbol: o["symbol"]
        }
      end)
    )
    |> prepare_changes(fn changeset ->
      system_symbol = fetch_field!(changeset, :system_symbol)

      changeset =
        case get_field(changeset, :orbits) do
          nil ->
            changeset

          orbits ->
            orbits_changeset =
              change(orbits, %{system_symbol: system_symbol})

            put_assoc(changeset, :orbits, orbits_changeset)
        end

      changeset
    end)
    |> assoc_constraint(:orbits)
  end

  def distance(%__MODULE__{} = a, %__MODULE__{} = b) do
    :math.sqrt(
      :math.pow(a.x_coordinate - b.x_coordinate, 2) +
        :math.pow(a.y_coordinate - b.y_coordinate, 2)
    )
  end
end
