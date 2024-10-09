defmodule SpacetradersClientWeb.AgentComponent do
  alias SpacetradersClient.Cldr.Number
  alias SpacetradersClientWeb.CreditBalanceComponent
  alias Motocho.Statements
  alias Motocho.Account
  alias Motocho.Ledger
  use SpacetradersClientWeb, :live_component

  def render(assigns) do
    ~H"""
    <section class="p-8 h-full w-full overflow-y-auto">
      <header class="mb-4">
        <h2 class="text-neutral-500">Agent</h2>
        <h1 class="text-2xl"><%= @agent["symbol"] %></h1>
      </header>

      <div class="flex flex-row gap-8 w-full mb-8">

        <div class="h-96 mb-8 basis-2/3">
          <h4 class="text-xl font-bold mb-4">Assets (Past Hour)</h4>
          <%= if @ledger do %>
            <%
              chart_cfg = %{
                type: "line",
                data: %{
                  datasets: account_type_datasets(@ledger, :assets)
                },
                options: %{
                  responsive: true,
                  elements: %{ point: %{ pointStyle: false } },
                  scales: %{
                    x: %{ type: "time", time: %{unit: "minute"}, suggestedMin: DateTime.to_iso8601(DateTime.add(DateTime.utc_now(), -1, :hour)) },
                    y: %{ stacked: true, suggestedMin: ((Ledger.balance(@ledger, "Fleet") |> elem(0)) * 0.75) }
                  }
                }
              }
            %>

            <canvas id="credits-history" phx-hook="Chart" data-config={Jason.encode!(chart_cfg)} height="400" width="600"></canvas>

          <% end %>

        </div>
        <div class="basis-1/3">
          <%= if @ledger do %>
            <h4 class="text-xl font-bold mb-4">Income (Past Hour)</h4>

            <.income_statement ledger={@ledger} />
          <% end %>
        </div>
        <div class="basis-1/3">
          <%= if @ledger do %>
            <h4 class="text-xl font-bold mb-4">Balances</h4>

            <.trial_balance_table ledger={@ledger} />
          <% end %>
        </div>
      </div>

      <%= if @ledger do %>
        <.tablist
          active_tab_id={@tab}
          target={@myself}
          tabs={[
            "Cash",
            "Merchandise",
            "Sales",
            "Fleet",
            "Natural Resources",
            "Starting Balances",
            "Cost of Merchandise Sold",
            "Fuel"
          ] |> Enum.map(fn name -> {name, name} end)}
        />


        <div>
          <.ledger_account_entries ledger={@ledger} account_name={@tab} />
        </div>
      <% end %>

    </section>
    """
  end

  def income_statement(assigns) do
    ~H"""
    <div>
      <% income = Statements.income_statement(@ledger, DateTime.add(DateTime.utc_now(), -1, :hour), DateTime.utc_now()) %>


      <table class="table table-sm">
        <tbody>
          <tr>
            <th>Revenue</th>
            <td></td>
          </tr>
          <%= for %{account: %{name: name}, balance: amount} <- income.revenues do %>
            <tr>
              <td>
                <%= name %>
              </td>
              <td class="text-right">
                <%= Number.to_string! amount, format: :accounting, fractional_digits: 0 %>
              </td>
            </tr>
          <% end %>
          <tr class="border-t-2">
            <th>Total Revenue</th>
            <td class="text-right font-bold">
              <%= Number.to_string! income.total_revenue, format: :accounting, fractional_digits: 0 %>
            </td>
          </tr>
          <%= for %{account: %{name: name}, balance: amount} <- income.direct_costs do %>
            <tr>
              <td>
                <%= name %>
              </td>
              <td class="text-right">
                <%= Number.to_string! amount, format: :accounting, fractional_digits: 0 %>
              </td>
            </tr>
          <% end %>
          <tr class="border-t-2">
            <th>Gross Profit</th>
            <td class="text-right font-bold">
              <%= Number.to_string! income.gross_profit, format: :accounting, fractional_digits: 0 %>
            </td>
          </tr>
          <%= for %{account: %{name: name}, balance: amount} <- income.expenses do %>
            <tr>
              <td>
                <%= name %>
              </td>
              <td class="text-right">
                <%= Number.to_string! amount, format: :accounting, fractional_digits: 0 %>
              </td>
            </tr>
          <% end %>
          <tr class="border-t-2">
            <th>Net Earnings</th>
            <td class="text-right font-bold">
              <%= Number.to_string! income.net_earnings, format: :accounting, fractional_digits: 0 %>
            </td>
          </tr>
        </tbody>
      </table>
    </div>
    """
  end

  def balance_sheet(assigns) do
    ~H"""
    <div>
      <% balance_sheet = Statements.balance_sheet(@ledger) %>
      <table>
        <tbody>
          <%= for {acct, bal} <- balance_sheet.assets.current do %>
            <tr>
              <td><%= acct.name %></td>
              <td>
                <%= Number.to_string! bal, format: :accounting, fractional_digits: 0 %>
              </td>
            </tr>
          <% end %>
          <tr>
          </tr>
        </tbody>
      </table>
    </div>
    """
  end

  def trial_balance_table(assigns) do
    ~H"""
    <table class="table table-sm">
      <thead>
        <tr>
          <td>Account</td>
          <td class="text-right">Debit</td>
          <td class="text-right">Credit</td>
        </tr>
      </thead>
      <tbody>
        <.ledger_account_row ledger={@ledger} account_name="Cash" />
        <.ledger_account_row ledger={@ledger} account_name="Merchandise" />
        <.ledger_account_row ledger={@ledger} account_name="Sales" />
        <.ledger_account_row ledger={@ledger} account_name="Natural Resources" />
        <.ledger_account_row ledger={@ledger} account_name="Starting Balances" />
        <.ledger_account_row ledger={@ledger} account_name="Cost of Merchandise Sold" />
        <.ledger_account_row ledger={@ledger} account_name="Fuel" />
      </tbody>

    </table>
    """
  end

  attr :ledger, :map, required: true
  attr :account_name, :string, required: true

  def ledger_account_row(assigns) do
    ~H"""
    <tr>
      <% account = Ledger.account(@ledger, @account_name) %>
      <% {dr, cr} = Account.value(account, Ledger.balance(@ledger, @account_name)) %>
      <td><%= @account_name %></td>
      <td class="text-right">
        <%= if trunc(dr) != 0 do %>
          <%= Number.to_string!(dr, format: :accounting, fractional_digits: 0) %>
        <% end %>
      </td>
      <td class="text-right">
        <%= if trunc(cr) != 0 do %>
          <%= Number.to_string!(cr, format: :accounting, fractional_digits: 0) %>
        <% end %>
      </td>
    </tr>
    """
  end

  attr :ledger, :map, required: true
  attr :account_name, :string, required: true

  def ledger_account_entries(assigns) do
    ~H"""
    <%
      account = Ledger.account(@ledger, @account_name)
      transactions = account_txns(@ledger, account.id)
    %>
    <h3 class="text-xl mb-4"><%= @account_name %></h3>

    <table class="table table-zebra table-sm">
      <thead>
        <tr>
          <th class="w-32">Timestamp</th>
          <th>Description</th>
          <th class="text-right w-28">Debit</th>
          <th class="text-right w-28">Credit</th>

        </tr>
      </thead>
      <tbody>
        <%= for txn <- Enum.sort_by(transactions, fn t -> t.date end, {:desc, DateTime}) do %>
          <tr>
            <td><%= txn.date %></td>
            <td>
              <%= txn.description %>
            </td>
            <%= if txn.debit_account_id == account.id do %>
              <td class="text-right">
                <%= Number.to_string!(txn.amount, format: :accounting, fractional_digits: 0) %>
              </td>
              <td></td>
            <% else %>
              <td></td>
              <td class="text-right">
                <%= Number.to_string!(txn.amount, format: :accounting, fractional_digits: 0) %>
              </td>
            <% end %>
          </tr>
        <% end %>
      </tbody>
    </table>

    """
  end

  attr :id, :string, required: true
  attr :amount, :integer, required: true

  def mount(socket) do
    {:ok, assign(socket, :tab, "Cash")}
  end

  defp account_txns(ledger, account_id) do
    ledger.transactions
    |> Enum.filter(fn txn ->
      txn.debit_account_id == account_id ||
        txn.credit_account_id == account_id
    end)
    |> Enum.sort_by(fn txn -> txn.date end, :desc)
  end

  defp account_type_datasets(ledger, type) do
    accounts =
      Enum.filter(ledger.accounts, fn {_id, account} ->
        account.type == type
      end)

    account_ids = Enum.map(accounts, fn {id, _acct} -> id end)


    journals =
      ledger.transactions
      |> Enum.filter(fn txn ->
        txn.debit_account_id in account_ids ||
          txn.credit_account_id in account_ids
      end)
      |> Enum.map(fn txn ->
        {txn, %{
          txn.debit_account_id => txn.amount,
          txn.credit_account_id => -txn.amount
        }}
      end)
      |> Enum.sort_by(fn {txn, _deltas} -> txn.date end, {:asc, DateTime})
      |> Enum.scan({nil, %{}}, fn {txn, amounts}, {_last_date, total_amounts} ->
        total_amounts =
          Enum.reduce(amounts, total_amounts, fn {acct_id, delta}, total_amounts ->
            total_amounts
            |> Map.put_new(acct_id, 0)
            |> Map.update!(acct_id, &(&1 + delta))
          end)

        {txn, total_amounts}
      end)
      |> Enum.map(fn {txn, amounts} ->
        %{x: txn.date}
        |> Map.merge(amounts)
      end)

    Enum.map(accounts, fn {account_id, account} ->
      %{
        label: account.name,
        data: journals,
        parsing: %{yAxisKey: account_id},
        fill: true
      }
    end)
    |> Enum.sort_by(fn dataset ->
      Enum.find_index(["Fleet", "Cash", "Merchandise"], fn name -> dataset.label == name end)
    end)
  end

  def handle_event("select-tab", %{"tab" => tab}, socket) do
    {:noreply, assign(socket, :tab, tab)}
  end

end
