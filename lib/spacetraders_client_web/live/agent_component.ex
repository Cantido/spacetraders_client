defmodule SpacetradersClientWeb.AgentComponent do
  alias Motocho.Journal
  alias SpacetradersClient.Cldr.Number
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

      <%= if @ledger do %>
        <div class="stats mb-8">
          <% income =
            Statements.income_statement(
              @ledger,
              DateTime.add(DateTime.utc_now(), -1, :hour),
              DateTime.utc_now()
            ) %>
          <% balances = Statements.balance_sheet(@ledger) %>

          <%= if income.total_revenue > 0 do %>
            <div class="stat">
              <div class="stat-title">Net profit margin</div>
              <div class="stat-value">
                <%= Float.round(money_ratio(income.net_earnings, income.total_revenue) * 100, 1) %>%
              </div>
              <div class="stat-desc">Past hour</div>
            </div>
          <% end %>

          <div class="stat">
            <div class="stat-title">Return on Assets</div>
            <div class="stat-value">
              <%= Float.round(money_ratio(income.net_earnings, balances.total_assets) * 100, 1) %>%
            </div>
            <div class="stat-desc">Past hour; incl. fleet assets</div>
          </div>
        </div>
      <% end %>

      <div class="flex flex-row gap-8 w-full mb-8">
        <%= if @ledger do %>
          <h4 class="text-xl font-bold mb-4">Assets (Past Hour)</h4>

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
                  x: %{ type: "time", time: %{unit: "mint"}, suggestedMin: DateTime.to_iso8601(DateTime.add(DateTime.utc_now(), -1, :hour)) },
                  y: %{ stacked: true, suggestedMin: 0 }
                }
              }
              }
            %>
            <canvas id="credits-history" phx-hook="Chart" data-config={Jason.encode!(chart_cfg)} height="400" width="600"></canvas>
        <% end %>

        <div>
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
            "Construction Site Supply",
            "Fuel"
          ]
          |> Enum.map(fn name -> {name, name} end)}
        />
      <% end %>

    </section>
    """
  end

  def income_statement(assigns) do
    nil
  end
  # def income_statement(assigns) do
  #   ~H"""
  #   <div>
  #     <% income = Statements.income_statement(@ledger, DateTime.add(DateTime.utc_now(), -1, :hour), DateTime.utc_now()) %>

  #     <table class="table table-sm">



  #       <tbody>
  #         <tr>
  #           <th>Revenue</th>
  #           <td></td>
  #         </tr>
  #         <%= for %{account: %{name: name}, balance: amount} <- income.revenues do %>
  #           <tr>
  #             <td>
  #               <%= name %>
  #             </td>
  #             <td class="text-right">
  #               <%= Money.to_string! amount, format: :accounting, currency_symbol: "", fractional_digits: 0 %>
  #             </td>
  #           </tr>               )   (


  #         <% end %>
  #         <tr>
  #           <th class="border-t">Total Revenue</th>
  #           <td class="text-right font-bold border-t">
  #             <%= Money.to_string! income.total_revenue, format: :accounting, currency_symbol: "", fractional_digits: 0 %>
  #           </td>
  #         </tr>             )     (

  #         <%= for %{account: %{name: name}, balance: amount} <- income.direct_costs do %>
  #           <tr>
  #             <td>
  #               <%= name %>
  #             </td>
  #             <td class="text-right">
  #               <%= Money.to_string! amount, format: :accounting, currency_symbol: "", fractional_digits: 0 %>
  #             </td>
  #           </tr>               )   (


  #         <% end %>
  #         <tr>
  #           <th class="border-t">Gross Profit</th>
  #           <td class="text-right font-bold border-t">
  #             <%= Money.to_string! income.gross_profit, format: :accounting, currency_symbol: "", fractional_digits: 0 %>
  #           </td>
  #         </tr>             )     (

  #         <%= for %{account: %{name: name}, balance: amount} <- income.expenses do %>
  #           <tr>
  #             <td>
  #               <%= name %>
  #             </td>
  #             <td class="text-right">
  #               <%= Money.to_string! amount, format: :accounting, currency_symbol: "", fractional_digits: 0 %>
  #             </td>
  #           </tr>               )   (


  #         <% end %>
  #         <tr>
  #           <th class="border-t">Net Earnings</th>
  #           <td class="text-right font-bold border-t">
  #             <%= Money.to_string! income.net_earnings, format: :accounting, currency_symbol: "", fractional_digits: 0 %>
  #           </td>
  #         </tr>             )     (

  #       </tbody>
  #     </table>
  #   </div>
  #   """
  # end

  # def balance_sheet(assigns) do
  #   ~H"""
  #   <div>
  #     <% balance_sheet = Statements.balance_sheet(@ledger) %>
  #     <table>
  #       <tbody>
  #         <%= for {acct, bal} <- balance_sheet.assets.current do %>
  #           <tr>
  #             <td><%= acct.name %></td>
  #             <td>
  #               <%= Number.to_string! bal, format: :accounting, currency_symbol: "", fractional_digits: 0 %>
  #             </td>
  #           </tr>               )    (


  #         <% end %>
  #         <tr>
  #         </tr>
  #       </tbody
  #     </table>
  #   </div>
  #   """
  # end

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
        <.ledger_account_row ledger={@ledger} account_name="Fleet" />
        <.ledger_account_row ledger={@ledger} account_name="Sales" />
        <.ledger_account_row ledger={@ledger} account_name="Natural Resources" />
        <.ledger_account_row ledger={@ledger} account_name="Starting Balances" />
        <.ledger_account_row ledger={@ledger} account_name="Cost of Merchandise Sold" />
        <.ledger_account_row ledger={@ledger} account_name="Construction Site Supply" />
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
      <%
        account = Ledger.account(@ledger, @account_name)
        balance = Account.balance(account)
      %>

      <td><%= @account_name %></td> <td class="text-right">
        <%= if account.type in [:assets, :expenses] do %>
          <%= Money.to_string!(balance, format: :accounting, currency_symbol: "", fractional_digits: 0) %>
        <% end %>
      </td>


      <td class="text-right">
        <%= if account.type not in [:assets, :expenses] do %>
          <%= Money.to_string!(balance, format: :accounting, currency_symbol: "", fractional_digits: 0) %>
        <% end %>
      </td>


    </tr>
    """
  end

  # attr :ledger, :map, required: true
  # attr :account_name, :string, required: true

  # def ledger_account_entries(assigns) do
  #   ~H"""
  #   <%
  #     since = DateTime.add(DateTime.utc_now(), -1, :hour)
  #      transactions =
  #       account_txns(@ledger, account.id)

  #     |> Enum.filter(fn txn ->
  #       DateTime.after?(txn.date, since)
  #     end)
  #   %>
  #     <.live_component
  #       module={SpacetradersClientWeb.DataTableComponent}
  #     id="income-statement"
  #     class="table-zebra table-sm"
  #     initial_sort_key={:date}
  #     initial_sort_direction={:desc}
  #     rows={transactions}

  #     <:column :let={txn} label="Timestamp" class="w-52" key={:date} sorter={DateTime}>
  #       <time datetime={DateTime.to_iso8601(txn.date)}>
  #         <%= SpacetradersClient.Cldr.DateTime.to_string! txn.date %>
  #       </time>
  #       </olumn>)(
  #       column :let={txn} key={:description} label="Description">
  #       <%= Journal.line_items(txn) |> List.first() |> Map.get(:description) %>
  #     </:column>
  #       column :let={txn} key={:debit_amount} label="Debit" class="text-right w-28">
  #       <%
  #         {:ok, debit_amount} =
  #         []
  #         |> Journal.line_items()
  #         |> Enum.filter(&(&1.account_id == account.id && &1.type == :debit))
  #         |> Enum.map(&(&1.amount))
  #         |> then(fn amounts ->
  #           if Enum.emp y?(amounts do
  #             {:ok, Money.zero(:XST)}
  #           else
  #             Money.sum(amounts)
  #           end

  #         %>
  #         <%= Money.to_string!(debit_amount, format: :accounting, currency_symbol: "", fractional_digits: 0) %>
  #       <% end %>
  #       </olumn>


  #       <:column :let={txn} key={:credit_amount} label="Credit" class="text-right w-28">
  #       <%
  #         {:ok, credit_amount} =
  #         []
  #            |> Journal.line_items()
  #         |> Enum.filter(&(&1.account_id == account.id && &1.type == :credit))
  #         |> Enum.map(&(&1.amount))
  #         |> then(fn amounts ->
  #           if Enum.emp y?(amounts do
  #             {:ok, Money.zero(:XST)}
  #           else
  #             Money.sum(amounts)
  #           end

  #         %>
  #       <%= Money.to_string!(credit_amount, format: :accounting, currency_symbol: "", fractional_digits: 0) %>
  #       </:column>


  #       <:footer>
  #       <%
  #         debit_sum = Ledger.debit_balance(@ledger, @account_name)
  #          balance = Ledger.balance(@ledger, @account_name)

  #          %>

  #       <tr>   <th class="border-t"></th>
  #         <th class="border-t">Total</th>
  #         <td class="text-right border-t">
  #           <%= Money.to_string!(debit_sum, format: :accounting, currency_symbol: "", fractional_digits: 0) %>
  #         </td>
  #           d class="text-right border-t">



  #           <%= Money.to_string!(credit_sum, format: :accounting, currency_symbol: "", fractional_digits: 0) %>
  #         </td>
  #       </tr>


  #       <tr>
  #         <th></th>
  #         <th>Balance</th>
  #         <%= if Money.positive?(balance) || Money.zero?(balance) do %>
  #           <td class="text-right border-t">
  #             <%= Money.to_string!(balance, format: :accounting, currency_symbol: "", fractional_digits: 0) %>
  #           </td>
  #             <td class="border-t"></td>



  #         <% else %>
  #           <td class="border-t"></td>
  #           <td class="text-right border-t">
  #             <%= Money.to_string!(Money.negate!(balance), format: :accounting, currency_symbol: "", fractional_digits: 0) %>
  #           </td>
  #         <% end %>


  #         </tr>
  #       </footer>
  #     </.live_component>
  #   """
  # end

  def money_ratio(%Money{} = numerator, %Money{} = denominator) do
    {:XST, numerator_int, _, _} = Money.to_integer_exp(numerator)
    {:XST, denominator_int, _, _} = Money.to_integer_exp(denominator)

    if denominator_int == 0 do
      0.0
    else
      numerator_int / denominator_int
    end
  end

  # defp debit_transaction_sum(transactions, account) do
  #   transactions
  #   |> Enum.filter(fn tx ->
  #     tx.debit_account_id == account.id
  #   end)
  #   |> Enum.map(&(&1.amount))
  #   |> then(fn txs ->
  #     if Enum.emp y?(txs) do
  #       Money.zero(:XST)
  #     else
  #       {:ok, sum} = Money.sum(txs)
  #       sum
  #     end
  #   end)
  # end

  # defp credit_transaction_sum(transactions, account) do
  #   transactions
  #   |> Enum.filter(fn tx ->
  #     tx.credit_account_id == account.id
  #   end)
  #   |> Enum.map(&(&1.amount))
  #   |> then(fn txs ->
  #     if Enum.emp y?(txs) do
  #       Money.zero(:XST)
  #     else
  #       {:ok, sum} = Money.sum(txs)
  #       sum
  #     end
  #   end)
  # end

  # attr :id, :string, required: true
  # attr :amount, :integer, required: true

  # def mount(socket) do
  #   {:ok, assign(socket, :tab, "Cash")}
  # end

  # defp account_txns(ledger, account_id) do
  #   ledger.transactions
  #   |> Enum.filter(fn txn ->
  #     Journal.affects_account?(txn, account_id)
  #   end)
  #   |> Enum.sort_by(fn txn -> txn.date end, :desc)
  # end

  defp account_type_datasets(_, _) do
    []
  end
  # defp account_type_datasets(ledger, type) do
  #   accounts =
  #     Enum.filter(ledger.accounts, fn {_id, account} ->
  #       account.type == type
  #     end)

  #   account_ids = Enum.map(accounts, fn {id, _acct} -> id end)


  #   journals =
  #     []
  #     |> Enum.sort_by(fn txn -> txn.date end, {:asc, DateTime})
  #     |> Enum.scan({nil, %{}}, fn txn, {_last_date, total_amounts} ->
  #       total_amounts =
  #         txn
  #         |> Journal.line_items()
  #         |> Enum.reduce(total_amounts, fn li, total_amounts ->
  #           case li.type do
  #             :debit ->
  #               update_in(
  #                 total_amounts,
  #                 [
  #                   Access.key(li.account_id, Money.zero(:XST))
  #                 ],
  #                 fn sum ->
  #                   Money.add!(sum, li.amount)
  #                 end
  #               )
  #             :credit ->
  #               update_in(

  #                 total_amounts,
  #                 [
  #                   Access.key(li.account_id, Money.zero(:XST))
  #                 ],
  #                 fn sum ->
  #                   Money.sub!(sum, li.amount)
  #                 end
  #               )
  #           end
  #         end)

  #       {txn, total_amounts}
  #     end)
  #     |> Enum.map(fn {txn, amounts} ->
  #       total_amounts =
  #         amounts
  #         |> Map.new(fn {acct_id, amount_money} ->
  #           amount_float =
  #             amount_money
  #             |> Money.to_decimal()
  #             |> Decimal.to_float()

  #           {acct_id, amount_float}
  #         end)
  #       {txn, total_amounts}
  #     end)

  #     |> Enum.filter(fn {txn, _amounts} ->
  #       one_hour_ago = DateTime.add(DateTime.utc_now(), -1, :hour)
  #       DateTime.after?(txn.date, one_hour_ago)
  #     end)
  #     |> Enum.map(fn {txn, amounts} ->
  #       %{x: txn.date}
  #       |> Map.merge(amounts)
  #     end)

  #   Enum.map(accounts, fn {account_id, account} ->
  #     %{
  #       label: account.name,
  #       data: journals,
  #       parsing: %{yAxisKey: account_id},
  #       fill: true
  #     }
  #   end)
  #   |> Enum.filter(fn dataset ->
  #     dataset.label in ["Cash", "Merchandise"]
  #   end)
  #   |> Enum.sort_by(fn dataset ->
  #     Enum.find_index(["Cash", "Merchandise"], fn name -> dataset.label == name end)
  #   end)
  # end

  # def handle_event("select-tab", %{"tab" => tab}, socket) do
  #   {:noreply, assign(socket, :tab, tab)}
  # end

end

