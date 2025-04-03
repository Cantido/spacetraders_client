alias SpacetradersClient.Client
alias SpacetradersClient.Fleet

defmodule Miner do
  def fulfill_contract(client, ship_symbol) do
    {:ok, %{status: 200}} = Client.enter_orbit(client, ship_symbol)

    :ok = mine_until_full(client, ship_symbol)

    {:ok, %{body: body, status: 200}} =
      Client.navigate_to_waypoint(client, ship_symbol, "X1-BU22-H54")
  end

  def mine_until_full(client, ship_symbol) do
    {:ok, cargo_resp = %{status: 200}} = Fleet.get_ship_cargo(client, ship_symbol)

    cargo_data =
      Map.fetch!(cargo_resp, :body)
      |> Map.fetch!("data")

    cargo_capacity = Map.fetch!(cargo_data, "capacity")
    cargo_used = Map.fetch!(cargo_data, "units")

    if cargo_used / cargo_capacity < 0.90 do
      {:ok, resp} = Client.extract_resources(client, ship_symbol)

      case resp.status do
        201 ->
          data =
            Map.fetch!(resp, :body)
            |> Map.fetch!("data")

          cargo_capacity = get_in(data, ["cargo", "capacity"])
          cargo_used = get_in(data, ["cargo", "units"])

          if cargo_used / cargo_capacity >= 0.90 do
            cargo_inventory = get_in(data, ["cargo", "inventory"])

            IO.puts("Mining successful. Done mining, got cargo:")

            Enum.each(cargo_inventory, fn item ->
              IO.puts("- #{item["units"]} #{item["name"]}")
            end)
          else
            remaining_seconds =
              get_in(data, ["cooldown", "remainingSeconds"])

            IO.puts(
              "Mining successful: got #{get_in(data, ["extraction"])}, cargo at #{Float.round(cargo_used / cargo_capacity * 100, 2)}%, cooling down for #{remaining_seconds} seconds..."
            )

            Process.sleep(:timer.seconds(remaining_seconds))

            mine_until_full(client, ship_symbol)
          end

        409 ->
          remaining_seconds =
            Map.fetch!(resp, :body)
            |> get_in(["error", "data", "remainingSeconds"])

          IO.puts(
            "Mining failed: still on cooldown. Sleeping for #{remaining_seconds} seconds..."
          )

          Process.sleep(:timer.seconds(remaining_seconds))

          mine_until_full(client, ship_symbol)
      end
    else
      :ok
    end
  end
end

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

:ok = Miner.fulfill_contract(client, "C0SM1C_R05E-3")
