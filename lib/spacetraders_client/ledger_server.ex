defmodule SpacetradersClient.LedgerServer do
  alias Motocho.Ledger
  alias Motocho.Journal
  alias Phoenix.PubSub
  use GenServer

  def start_link(_) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def init([]) do
    {:ok, %{ledgers: %{}}}
  end

  def start_ledger(agent_id, starting_credits, starting_fleet_value, starting_merchandise) do
    GenServer.call(__MODULE__, {:start_ledger, agent_id, starting_credits, starting_fleet_value, starting_merchandise})
  end

  def ledger(agent_id) do
    GenServer.call(__MODULE__, {:get_ledger, agent_id})
  end

  def post_journal(agent_id, date, description, debit_account, credit_account, amount) do
    GenServer.call(
      __MODULE__,
      {:post_journal, agent_id, date, description, debit_account, credit_account, amount}
    )
  end

  def handle_call({:get_ledger, agent_id}, _from, state) do
    if ledger = get_in(state, [:ledgers, agent_id]) do
      {:reply, {:ok, ledger}, state}
    else
      {:reply, {:error, :ledger_not_found}, state}
    end
  end

  def handle_call({:start_ledger, agent_id, starting_credits, starting_fleet, starting_merchandise}, _from, state) do
    if Map.has_key?(state.ledgers, agent_id) do
      {:reply, {:error, :ledger_exists}, state}
    else
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
              cash_account,
              starting_account,
              starting_credits
            ),
            Journal.simple(
              DateTime.utc_now(),
              "Starting Fleet Value",
              fleet_account,
              starting_account,
              starting_fleet
            ),
            Journal.simple(
              DateTime.utc_now(),
              "Starting Merchandise Value",
              merch_account,
              starting_account,
              starting_merchandise
            )
          ]
          |> Enum.reduce(ledger, &Ledger.post(&2, &1))
        end)

      {:reply, {:ok, state.ledgers[agent_id]}, state, {:continue, {:broadcast_update, agent_id}}}
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

          journal = Journal.simple(date, description, dr_acct, cr_acct, amount)

          Ledger.post(ledger, journal)
        end)

      {:reply, {:ok, state.ledgers[agent_id]}, state, {:continue, {:broadcast_update, agent_id}}}
    else
      {:reply, {:error, {:ledger_not_found}}}
    end
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
      put_in(state, [:ledgers, agent_id], start_ledger())
    end
  end

  defp start_ledger do
    Ledger.new()
    |> Ledger.open_account("Cash", :assets, number: 1000)
    |> Ledger.open_account("Fleet", :assets, number: 1200)
    |> Ledger.open_account("Merchandise", :assets, number: 1500)
    |> Ledger.open_account("Sales", :revenue, number: 4000)
    |> Ledger.open_account("Natural Resources", :revenue, number: 4900)
    |> Ledger.open_account("Starting Balances", :equity, number: 3900)
    |> Ledger.open_account("Cost of Merchandise Sold", :expenses, direct_cost: true, number: 5000)
    |> Ledger.open_account("Fuel", :expenses, number: 6000)
  end
end
