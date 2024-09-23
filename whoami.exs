alias SpacetradersClient.Client

token =
  if token = System.get_env("SPACETRADERS_TOKEN") do
    token
  else
    IO.gets("Enter SpaceTraders token: ")
  end

client =
  token
  |> String.trim()
  |> Client.new()

{:ok, resp} = Client.waypoints(client, "X1-TZ13")

resp
|> Map.get(:body)
|> IO.inspect(prettty: true)
