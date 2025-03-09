defmodule SpacetradersClient.Cldr do
  use Cldr,
    otp_app: :spacetraders_client,
    providers: [Cldr.Calendar, Cldr.DateTime, Cldr.Number, Money]
end
