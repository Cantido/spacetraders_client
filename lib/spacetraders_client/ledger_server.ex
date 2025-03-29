defmodule SpacetradersClient.LedgerServer do
  alias SpacetradersClient.Game
  alias SpacetradersClient.Game.Agent
  alias SpacetradersClient.Repo
  alias Motocho.Account
  alias Motocho.Inventory
  alias Motocho.Ledger
  alias Motocho.Journal
  alias Phoenix.PubSub
  use GenServer

  def start_link(_) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def init([]) do
    {:ok, %{ledgers: %{}, inventories: %{}}}
  end

  def ensure_started(agent_id) do
    GenServer.call(
      __MODULE__,
      {:ensure_started, agent_id}
    )
  end

  def start_ledger(agent_id) do
    GenServer.call(
      __MODULE__,
      {:start_ledger, agent_id}
    )
  end

  def ledger(agent_id) do
    GenServer.call(__MODULE__, {:get_ledger, agent_id}, 20_000)
  end

  def post_journal(agent_id, date, description, debit_account, credit_account, amount)
      when is_integer(amount) do
    GenServer.call(
      __MODULE__,
      {:post_journal, agent_id, date, description, debit_account, credit_account, amount}
    )
  end

  def purchase_inventory_by_unit(agent_id, trade_symbol, date, quantity, cost_per_unit)
      when is_integer(cost_per_unit) do
    GenServer.call(
      __MODULE__,
      {:buy_inventory_unit, agent_id, trade_symbol, date, quantity, cost_per_unit}
    )
  end

  def purchase_inventory_by_total(agent_id, trade_symbol, date, quantity, total_cost)
      when is_integer(total_cost) do
    GenServer.call(
      __MODULE__,
      {:buy_inventory_total, agent_id, trade_symbol, date, quantity, total_cost}
    )
  end

  def sell_inventory(agent_id, trade_symbol, date, quantity, total_amount)
      when is_integer(total_amount) do
    GenServer.call(
      __MODULE__,
      {:sell_inventory, agent_id, trade_symbol, date, quantity, total_amount}
    )
  end

  def supply_construction_site(agent_id, trade_symbol, date, quantity) do
    GenServer.call(
      __MODULE__,
      {:supply_construction_site, agent_id, trade_symbol, date, quantity}
    )
  end

  def handle_call({:ensure_started, agent_id}, _from, state) do
    if Map.has_key?(state.ledgers, agent_id) do
      {:reply, :ok, state}
    else
      {:reply, :ok, state, {:continue, {:start_ledger, agent_id}}}
    end
  end

  def handle_call({:get_ledger, agent_id}, _from, state) do
    if ledger = get_in(state, [:ledgers, agent_id]) do
      {:reply, {:ok, ledger}, state}
    else
      {:reply, {:error, :ledger_not_found}, state}
    end
  end

  def handle_call(
        {:start_ledger, agent_id},
        _from,
        state
      ) do
    if Map.has_key?(state.ledgers, agent_id) do
      {:reply, {:error, :ledger_exists}, state}
    else
      {:reply, :ok, state, {:continue, {:start_ledger, agent_id}}}
    end
  end

  def handle_call(
        {:post_journal, agent_id, date, description, debit_account, credit_account, amount},
        _from,
        state
      ) do
    if Map.has_key?(state.ledgers, agent_id) do
      state =
        state
        |> update_in([:ledgers, agent_id], fn ledger ->
          dr_acct = Ledger.account(ledger, debit_account)
          cr_acct = Ledger.account(ledger, credit_account)

          journal =
            Journal.simple(date, description, dr_acct.id, cr_acct.id, Money.new(:XST, amount))

          Ledger.post(ledger, journal)
        end)

      {:reply, {:ok, state.ledgers[agent_id]}, state, {:continue, {:broadcast_update, agent_id}}}
    else
      {:reply, {:error, {:ledger_not_found}}, state}
    end
  end

  def handle_call(
        {:buy_inventory_unit, agent_id, trade_symbol, date, quantity, cost_per_unit},
        _from,
        state
      ) do
    state =
      update_in(
        state,
        [
          :inventories,
          Access.key(agent_id, %{}),
          Access.key(trade_symbol, Inventory.new(:XST))
        ],
        fn inventory ->
          Inventory.purchase_inventory_by_unit(
            inventory,
            date,
            quantity,
            Money.new(:XST, cost_per_unit)
          )
        end
      )

    {:reply, {:ok, get_in(state, [:inventories, agent_id, trade_symbol])}, state}
  end

  def handle_call(
        {:buy_inventory_total, agent_id, trade_symbol, date, quantity, total_cost},
        _from,
        state
      ) do
    state =
      update_in(
        state,
        [
          :inventories,
          Access.key(agent_id, %{}),
          Access.key(trade_symbol, Inventory.new(:XST))
        ],
        fn inventory ->
          Inventory.purchase_inventory_by_total(
            inventory,
            date,
            quantity,
            Money.new(:XST, total_cost)
          )
        end
      )

    {:reply, {:ok, get_in(state, [:inventories, agent_id, trade_symbol])}, state}
  end

  def handle_call(
        {:sell_inventory, agent_id, trade_symbol, date, quantity, total_amount},
        _from,
        state
      ) do
    state =
      state
      |> update_in([:ledgers, agent_id], fn ledger ->
        dr_acct = Ledger.account(ledger, "Cash")
        cr_acct = Ledger.account(ledger, "Sales")

        journal =
          Journal.simple(
            date,
            "SELL #{trade_symbol} × #{quantity}",
            dr_acct.id,
            cr_acct.id,
            Money.new(:XST, total_amount)
          )

        Ledger.post(ledger, journal)
      end)

    inventory =
      get_in(
        state,
        [
          :inventories,
          Access.key(agent_id, %{}),
          Access.key(trade_symbol, Inventory.new(:XST))
        ]
      )

    {inventory, row} = Inventory.sell_inventory(inventory, date, quantity)

    state =
      put_in(
        state,
        [
          :inventories,
          Access.key(agent_id, %{}),
          Access.key(trade_symbol)
        ],
        inventory
      )

    state =
      state
      |> update_in([:ledgers, agent_id], fn ledger ->
        dr_acct = Ledger.account(ledger, "Cost of Merchandise Sold")
        cr_acct = Ledger.account(ledger, "Merchandise")

        journal =
          Journal.simple(
            date,
            "COST OF GOODS SOLD #{trade_symbol} × #{quantity} @ #{row.cost_per_unit}/u",
            dr_acct.id,
            cr_acct.id,
            row.total_cost
          )

        Ledger.post(ledger, journal)
      end)

    {:reply, {:ok, get_in(state, [:inventories, agent_id, trade_symbol])}, state,
     {:continue, {:broadcast_update, agent_id}}}
  end

  def handle_call(
        {:supply_construction_site, agent_id, trade_symbol, date, quantity},
        _from,
        state
      ) do
    inventory =
      get_in(
        state,
        [
          :inventories,
          Access.key(agent_id, %{}),
          Access.key(trade_symbol, Inventory.new(:XST))
        ]
      )

    {inventory, row} = Inventory.sell_inventory(inventory, date, quantity)

    state =
      put_in(
        state,
        [
          :inventories,
          Access.key(agent_id, %{}),
          Access.key(trade_symbol)
        ],
        inventory
      )

    state =
      state
      |> update_in([:ledgers, agent_id], fn ledger ->
        dr_acct = Ledger.account(ledger, "Construction Site Supply")
        cr_acct = Ledger.account(ledger, "Merchandise")

        journal =
          Journal.simple(
            date,
            "SUPPLY CONSTRUCTION SITE #{trade_symbol} × #{quantity} @ #{row.cost_per_unit}/u",
            dr_acct.id,
            cr_acct.id,
            row.total_cost
          )

        Ledger.post(ledger, journal)
      end)

    {:reply, {:ok, get_in(state, [:inventories, agent_id, trade_symbol])}, state,
     {:continue, {:broadcast_update, agent_id}}}
  end

  def handle_continue({:start_ledger, agent_id}, state) do
    agent = Repo.get(Agent, agent_id)

    starting_credits = agent["credits"]
    starting_fleet = Game.fleet_value(agent_id)
    starting_merchandise = Game.merchandise_value(agent_id)

    merch_value =
      Enum.map(starting_merchandise, fn m -> m.total_cost end)
      |> Enum.sum()

    state =
      state
      |> ensure_ledger(agent_id)
      |> update_in([:ledgers, agent_id], fn ledger ->
        cash_account = Ledger.account(ledger, "Cash")
        fleet_account = Ledger.account(ledger, "Fleet")
        merch_account = Ledger.account(ledger, "Merchandise")
        starting_account = Ledger.account(ledger, "Starting Balances")

        [
          Journal.simple(
            DateTime.utc_now(),
            "Starting Credits Balance",
            cash_account.id,
            starting_account.id,
            Money.new(:XST, starting_credits)
          ),
          Journal.simple(
            DateTime.utc_now(),
            "Starting Fleet Value",
            fleet_account.id,
            starting_account.id,
            Money.new(:XST, trunc(starting_fleet))
          ),
          Journal.simple(
            DateTime.utc_now(),
            "Starting Merchandise Value",
            merch_account.id,
            starting_account.id,
            Money.new(:XST, trunc(merch_value))
          )
        ]
        |> Enum.reduce(ledger, &Ledger.post(&2, &1))
      end)

    state =
      Enum.reduce(starting_merchandise, state, fn merch, state ->
        update_in(
          state,
          [
            :inventories,
            Access.key(agent_id, %{}),
            Access.key(merch.trade_symbol, Inventory.new(:XST))
          ],
          fn inventory ->
            Inventory.purchase_inventory_by_total(
              inventory,
              DateTime.utc_now(),
              merch.units,
              Money.new(:XST, trunc(merch.total_cost))
            )
          end
        )
      end)

    {:noreply, state, {:continue, {:broadcast_update, agent_id}}}
  end

  def handle_continue({:broadcast_update, agent_id}, state) do
    if ledger = get_in(state, [:ledgers, agent_id]) do
      PubSub.broadcast(SpacetradersClient.PubSub, "agent:#{agent_id}", {:ledger_updated, ledger})
    end

    {:noreply, state}
  end

  defp ensure_ledger(state, agent_id) do
    if Map.has_key?(state.ledgers, agent_id) do
      state
    else
      put_in(state, [:ledgers, agent_id], zero_ledger())
    end
  end

  defp zero_ledger do
    Ledger.new()
    |> put_in([Access.key(:currency)], :XST)
    |> Ledger.add_account(Account.new("Cash", :assets, number: 1000))
    |> Ledger.add_account(Account.new("Fleet", :assets, number: 1200))
    |> Ledger.add_account(Account.new("Merchandise", :assets, number: 1500))
    |> Ledger.add_account(Account.new("Sales", :revenue, number: 4000))
    |> Ledger.add_account(Account.new("Natural Resources", :revenue, number: 4900))
    |> Ledger.add_account(Account.new("Starting Balances", :equity, number: 3900))
    |> Ledger.add_account(
      Account.new("Cost of Merchandise Sold", :expenses, direct_cost: true, number: 5000)
    )
    |> Ledger.add_account(
      Account.new("Construction Site Supply", :expenses, direct_cost: true, number: 5100)
    )
    |> Ledger.add_account(Account.new("Fuel", :expenses, number: 6000))
  end
end
