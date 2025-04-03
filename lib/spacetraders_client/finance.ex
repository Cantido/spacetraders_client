defmodule SpacetradersClient.Finance do
  alias SpacetradersClient.Game
  alias SpacetradersClient.Game.Agent
  alias SpacetradersClient.Game.Item
  alias SpacetradersClient.Finance.Account
  alias SpacetradersClient.Finance.Inventory
  alias SpacetradersClient.Finance.InventoryLineItem
  alias SpacetradersClient.Finance.Transaction
  alias SpacetradersClient.Repo

  import Ecto.Query

  def open_accounts(agent_symbol) do
    agent = Repo.get_by!(Agent, symbol: agent_symbol)

    if Repo.get_by(Account, agent_id: agent.id, name: "Cash") do
      :ok
    else
      do_open_accounts(agent_symbol)
    end
  end

  defp do_open_accounts(agent_symbol) do
    agent = Repo.get_by(Agent, symbol: agent_symbol)

    starting_credits = agent.credits
    starting_fleet = Game.fleet_value(agent_symbol)
    starting_merchandise = Game.merchandise_value(agent_symbol)

    merch_value =
      Enum.map(starting_merchandise, fn m -> m.total_cost end)
      |> Enum.sum()

    Repo.transaction(fn ->
      starting_accounts = [
        %{agent_id: agent.id, name: "Cash", type: :assets, number: 1000},
        %{agent_id: agent.id, name: "Fleet", type: :assets, number: 1200},
        %{agent_id: agent.id, name: "Merchandise", type: :assets, number: 1500},
        %{agent_id: agent.id, name: "Sales", type: :revenue, number: 4000},
        %{agent_id: agent.id, name: "Natural Resources", type: :revenue, number: 4900},
        %{agent_id: agent.id, name: "Starting Balances", type: :equity, number: 3900},
        %{
          agent_id: agent.id,
          name: "Cost of Merchandise Sold",
          type: :expenses,
          number: 5000
        },
        %{
          agent_id: agent.id,
          name: "Construction Site Supply",
          type: :expenses,
          number: 5100
        },
        %{agent_id: agent.id, name: "Fuel", type: :expenses, number: 6000}
      ]

      {9, accounts} = Repo.insert_all(Account, starting_accounts, returning: true)

      cash_account = Enum.find(accounts, fn a -> a.name == "Cash" end)
      fleet_account = Enum.find(accounts, fn a -> a.name == "Fleet" end)
      merch_account = Enum.find(accounts, fn a -> a.name == "Merchandise" end)
      starting_balance_account = Enum.find(accounts, fn a -> a.name == "Starting Balances" end)

      now = DateTime.utc_now()

      [
        Transaction.simple(
          now,
          "Starting Credits Balance",
          cash_account.id,
          starting_balance_account.id,
          starting_credits
        ),
        Transaction.simple(
          now,
          "Starting Fleet Value",
          fleet_account.id,
          starting_balance_account.id,
          starting_fleet
        ),
        Transaction.simple(
          now,
          "Starting Merchandise Value",
          merch_account.id,
          starting_balance_account.id,
          merch_value
        )
      ]
      |> Enum.each(fn tx ->
        Repo.insert!(tx)
      end)

      Enum.each(starting_merchandise, fn merch ->
        item = Repo.get_by!(Item, symbol: merch.trade_symbol)

        %Inventory{
          agent_id: agent.id,
          item_id: item.id
        }
        |> Repo.insert!()

        {:ok, _} =
          purchase_inventory_by_total(
            agent_symbol,
            merch.trade_symbol,
            now,
            merch.units,
            trunc(merch.total_cost)
          )
      end)
    end)
  end

  defp agent_account_by_name(agent_symbol, name) do
    Repo.one(
      from(a in Account,
        join: ag in assoc(a, :agent),
        where: ag.symbol == ^agent_symbol,
        where: a.name == ^name
      )
    )
  end

  def post_journal(
        agent_symbol,
        timestamp,
        description,
        debit_account_name,
        credit_account_name,
        amount
      ) do
    debit_account = agent_account_by_name(agent_symbol, debit_account_name)
    credit_account = agent_account_by_name(agent_symbol, credit_account_name)

    post_journal(
      timestamp,
      description,
      debit_account.id,
      credit_account.id,
      amount
    )
  end

  def post_journal(timestamp, description, debit_account_id, credit_account_id, amount) do
    Transaction.simple(
      timestamp,
      description,
      debit_account_id,
      credit_account_id,
      amount
    )
    |> Repo.insert()
  end

  def purchase_inventory_by_total(agent_symbol, item_symbol, timestamp, quantity, total_cost) do
    inventory =
      from(inv in Inventory,
        join: a in assoc(inv, :agent),
        join: i in assoc(inv, :item),
        where: a.symbol == ^agent_symbol,
        where: i.symbol == ^item_symbol
      )
      |> Repo.one!()

    %InventoryLineItem{
      inventory_id: inventory.id,
      timestamp: timestamp,
      quantity: quantity,
      cost_per_unit: div(total_cost, quantity),
      total_cost: total_cost
    }
    |> Repo.insert()
  end

  def purchase_inventory_by_unit(agent_symbol, item_symbol, timestamp, quantity, cost_per_unit) do
    inventory =
      from(inv in Inventory,
        join: a in assoc(inv, :agent),
        join: i in assoc(inv, :item),
        where: a.symbol == ^agent_symbol,
        where: i.symbol == ^item_symbol
      )
      |> Repo.one!()

    %InventoryLineItem{
      inventory_id: inventory.id,
      timestamp: timestamp,
      quantity: quantity,
      cost_per_unit: cost_per_unit,
      total_cost: quantity * cost_per_unit
    }
    |> Repo.insert!()
  end

  def sell_inventory(agent_symbol, item_symbol, timestamp, quantity, credits) do
    Repo.transaction(fn ->
      dr_acct = agent_account_by_name(agent_symbol, "Cash")
      cr_acct = agent_account_by_name(agent_symbol, "Sales")

      tx =
        post_journal(
          timestamp,
          "SELL #{item_symbol} × #{quantity}",
          dr_acct.id,
          cr_acct.id,
          credits
        )

      do_sell_inventory(agent_symbol, item_symbol, timestamp, quantity)

      tx
    end)
  end

  defp inventory(agent_symbol, item_symbol) do
    Repo.one(
      from(i in Inventory,
        join: a in assoc(i, :agent),
        join: item in assoc(i, :item),
        where: a.symbol == ^agent_symbol,
        where: item.symbol == ^item_symbol
      )
    )
  end

  defp do_sell_inventory(agent_symbol, item_symbol, timestamp, quantity) do
    Repo.transaction(fn ->
      inventory = inventory(agent_symbol, item_symbol)

      goods_available = goods_available_for_sale(agent_symbol)

      cpu = Map.get(goods_available, :cost_per_unit, 0)

      total_cost = -1 * cpu * quantity

      line_item =
        %InventoryLineItem{
          inventory_id: inventory.id,
          timestamp: timestamp,
          quantity: -1 * quantity,
          cost_per_unit: cpu,
          total_cost: total_cost
        }
        |> Repo.insert!()

      merch_dr_acct = agent_account_by_name(agent_symbol, "Cost of Merchandise Sold")
      merch_cr_acct = agent_account_by_name(agent_symbol, "Merchandise")

      post_journal(
        timestamp,
        "COST OF GOODS SOLD #{item_symbol} × #{quantity} @ #{line_item.cost_per_unit}/u",
        merch_dr_acct.id,
        merch_cr_acct.id,
        total_cost
      )

      line_item
    end)
  end

  defp goods_available_for_sale(agent_symbol) do
    goods_available =
      Repo.one(
        from(
          il in InventoryLineItem,
          join: i in assoc(il, :inventory),
          join: a in assoc(i, :agent),
          where: a.symbol == ^agent_symbol,
          select: %{
            quantity: sum(il.quantity),
            total_cost: sum(il.total_cost)
          }
        )
      )

    if goods_available.quantity > 0 do
      Map.put(
        goods_available,
        :cost_per_unit,
        div(goods_available.total_cost, goods_available.quantity)
      )
    else
      goods_available
    end
  end

  def supply_construction_site(agent_symbol, item_symbol, timestamp, quantity) do
    Repo.transaction(fn ->
      {:ok, line_item} = do_sell_inventory(agent_symbol, item_symbol, timestamp, quantity)

      dr_acct = agent_account_by_name(agent_symbol, "Construction Site Supply")
      cr_acct = agent_account_by_name(agent_symbol, "Merchandise")

      post_journal(
        timestamp,
        "SUPPLY CONSTRUCTION SITE #{item_symbol} × #{quantity} @ #{line_item.cost_per_unit}/u",
        dr_acct.id,
        cr_acct.id,
        line_item.total_cost
      )
    end)
  end

  def income_statement(agent_symbol, from, to) do
    revenues =
      Repo.all(
        from a in Account,
          join: ag in assoc(a, :agent),
          where: a.type == :revenue,
          where: ag.symbol == ^agent_symbol
      )
      |> Enum.map(fn account ->
        balance = account_balance(account.id, from, to)
        %{account: account, balance: balance}
      end)

    direct_costs =
      Repo.all(
        from a in Account,
          join: ag in assoc(a, :agent),
          where: a.type == :expenses,
          where: a.direct_cost,
          where: ag.symbol == ^agent_symbol
      )
      |> Enum.map(fn account ->
        balance = account_balance(account.id, from, to)
        %{account: account, balance: balance}
      end)

    expenses =
      Repo.all(
        from a in Account,
          join: ag in assoc(a, :agent),
          where: a.type == :expenses,
          where: not a.direct_cost,
          where: ag.symbol == ^agent_symbol
      )
      |> Enum.map(fn account ->
        balance = account_balance(account.id, from, to)
        %{account: account, balance: balance}
      end)

    total_revenue =
      Enum.map(revenues, fn acct_bal -> acct_bal.balance end)
      |> Enum.sum()

    costs =
      Enum.map(direct_costs, fn acct_bal -> acct_bal.balance end)
      |> Enum.sum()

    gross_profit = total_revenue - costs

    total_expenses =
      Enum.map(expenses, fn acct_bal -> acct_bal.balance end)
      |> Enum.sum()

    %{
      revenues: revenues,
      total_revenue: total_revenue,
      direct_costs: direct_costs,
      gross_profit: gross_profit,
      expenses: expenses,
      total_expenses: total_expenses,
      net_earnings: gross_profit - total_expenses
    }
  end

  def debit_balance(account_id) do
    Repo.one(
      from a in Account,
        join: li in assoc(a, :line_items),
        join: tx in assoc(li, :transaction),
        where: a.id == ^account_id,
        where: li.type == :debit,
        select: sum(li.amount)
    ) || 0
  end

  def credit_balance(account_id) do
    Repo.one(
      from a in Account,
        join: li in assoc(a, :line_items),
        join: tx in assoc(li, :transaction),
        where: a.id == ^account_id,
        where: li.type == :credit,
        select: sum(li.amount)
    ) || 0
  end

  def account_balance(account_id) do
    debit_balance =
      Repo.one(
        from a in Account,
          join: li in assoc(a, :line_items),
          join: tx in assoc(li, :transaction),
          where: a.id == ^account_id,
          where: li.type == :debit,
          select: sum(li.amount)
      ) || 0

    credit_balance =
      Repo.one(
        from a in Account,
          join: li in assoc(a, :line_items),
          join: tx in assoc(li, :transaction),
          where: a.id == ^account_id,
          where: li.type == :credit,
          select: sum(li.amount)
      ) || 0

    account = Repo.get(Account, account_id)

    case account.type do
      :assets -> debit_balance - credit_balance
      :liabilities -> credit_balance - debit_balance
      :equity -> credit_balance - debit_balance
      :revenue -> credit_balance - debit_balance
      :expenses -> debit_balance - credit_balance
    end
  end

  def account_balance(account_id, from, to) do
    debit_balance =
      Repo.one(
        from a in Account,
          join: li in assoc(a, :line_items),
          join: tx in assoc(li, :transaction),
          where: a.id == ^account_id,
          where: li.type == :debit,
          where: tx.timestamp >= ^from,
          where: tx.timestamp < ^to,
          select: sum(li.amount)
      ) || 0

    credit_balance =
      Repo.one(
        from a in Account,
          join: li in assoc(a, :line_items),
          join: tx in assoc(li, :transaction),
          where: a.id == ^account_id,
          where: li.type == :credit,
          where: tx.timestamp >= ^from,
          where: tx.timestamp < ^to,
          select: sum(li.amount)
      ) || 0

    account = Repo.get(Account, account_id)

    case account.type do
      :assets -> debit_balance - credit_balance
      :liabilities -> credit_balance - debit_balance
      :equity -> credit_balance - debit_balance
      :revenue -> credit_balance - debit_balance
      :expenses -> debit_balance - credit_balance
    end
  end

  def balance_sheet(_agent_symbol) do
    %{
      total_assets: 0,
      total_liabilities_and_equity: 0,
      assets: %{current: [], non_current: []},
      liabilities: %{current: [], non_current: []},
      equity: %{current: [], non_current: []}
    }
  end
end
