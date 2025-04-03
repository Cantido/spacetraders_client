defmodule SpacetradersClient.Game.MarketTradeGood do
  use Ecto.Schema

  alias SpacetradersClient.Game.Market
  alias SpacetradersClient.Game.Item

  import Ecto.Changeset

  schema "market_trade_goods" do
    belongs_to :market, Market

    belongs_to :item, Item

    field :type, Ecto.Enum, values: [export: "EXPORT", import: "IMPORT", exchange: "EXCHANGE"]
    field :trade_volume, :integer

    field :supply, Ecto.Enum,
      values: [
        scarce: "SCARCE",
        limited: "LIMITED",
        moderate: "MODERATE",
        high: "HIGH",
        abundant: "ABUNDANT"
      ]

    field :activity, Ecto.Enum,
      values: [weak: "WEAK", growing: "GROWING", strong: "STRONG", restricted: "RESTRICTED"]

    field :purchase_price, :integer
    field :sell_price, :integer

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(model, params) do
    model
    |> cast(params, [
      :type,
      :trade_volume,
      :supply,
      :activity,
      :purchase_price,
      :sell_price
    ])
    |> assoc_constraint(:market)
    |> assoc_constraint(:item)
    |> validate_required([:type])
    |> unique_constraint([:item_id, :market_id],
      name: "market_trade_goods_market_id_item_id_index",
      message: "market is already selling this item"
    )
  end
end
