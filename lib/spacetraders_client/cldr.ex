defmodule SpacetradersClient.Cldr do
  use Cldr,
    otp_app: :spacetraders_client,
    default_locale: "en",
    providers: [Cldr.Number]
end
