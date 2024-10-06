defmodule SpacetradersClient.Cache do
  use Nebulex.Cache,
    otp_app: :spacetraders_client,
    adapter: Nebulex.Adapters.Local
end
