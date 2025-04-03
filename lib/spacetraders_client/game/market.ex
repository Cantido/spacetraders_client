defmodule SpacetradersClient.Game.Market do
  use Ecto.Schema

  alias SpacetradersClient.Game.MarketTradeGood

  import Ecto.Changeset

  schema "markets" do
    field :symbol, :string
    has_many :items, MarketTradeGood

    has_many :trade_goods, MarketTradeGood,
      where: [sell_price: {:not, nil}, purchase_price: {:not, nil}]

    has_many :imports, MarketTradeGood, where: [type: :import]
    has_many :exports, MarketTradeGood, where: [type: :export]
    has_many :exchanges, MarketTradeGood, where: [type: :exchange]
  end

  def changeset(model, params) do
    items =
      if Enum.any?(Map.get(params, "tradeGoods", [])) do
        Enum.map(params["tradeGoods"], fn tg ->
          %{
            item_symbol: tg["symbol"],
            type: tg["type"],
            trade_volume: tg["tradeVolume"],
            supply: tg["supply"],
            activity: tg["activity"],
            purchase_price: tg["purchasePrice"],
            sell_price: tg["sellPrice"]
          }
        end)
      else
        exports =
          Enum.map(params["exports"], fn export ->
            %{item_symbol: export["symbol"], type: "EXPORT"}
          end)

        imports =
          Enum.map(params["imports"], fn import ->
            %{item_symbol: import["symbol"], type: "IMPORT"}
          end)

        exchanges =
          Enum.map(params["exchange"], fn exchange ->
            %{item_symbol: exchange["symbol"], type: "EXCHANGE"}
          end)

        imports ++ exports ++ exchanges
      end

    params = %{items: items}

    model
    |> cast(params, [])
    |> cast_assoc(:items)
  end
end
