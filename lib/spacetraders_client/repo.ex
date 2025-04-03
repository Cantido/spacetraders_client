defmodule SpacetradersClient.Repo do
  use Ecto.Repo,
    otp_app: :spacetraders_client,
    adapter: Ecto.Adapters.Postgres
end
