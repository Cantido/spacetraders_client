defmodule SpacetradersClientWeb.CreditsLive do
  use SpacetradersClientWeb, :live_view

  alias Phoenix.LiveView.AsyncResult
  alias Phoenix.PubSub
  alias SpacetradersClient.Agents
  alias SpacetradersClient.Client
  alias SpacetradersClient.Fleet
  alias SpacetradersClient.AutomationServer
  alias SpacetradersClient.AutomationSupervisor
  alias SpacetradersClient.AgentAutomaton
  alias SpacetradersClient.ShipAutomaton
  alias SpacetradersClient.LedgerServer
  alias Motocho.Journal
  alias SpacetradersClient.Cldr.Number
  alias Motocho.Statements
  alias Motocho.Account
  alias Motocho.Ledger

  @pubsub SpacetradersClient.PubSub

  def render(assigns) do
    ~H"""
      <.async_result :let={ledger} assign={@ledger}>
        <:loading><span class="loading loading-ring loading-lg"></span></:loading>
        <:failed :let={_failure}>There was an error loading the ledger.</:failed>
        <div :if={is_struct(ledger)} class="stats mb-8">
          <% income =
            Statements.income_statement(
              ledger,
              DateTime.add(DateTime.utc_now(), -1, :hour),
              DateTime.utc_now()
            ) %>
          <% balances = Statements.balance_sheet(ledger) %>

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

        <div class="flex flex-wrap gap-8">
          <div class="grow bg-base-300 p-4 rounded">
            <h4 class="text-xl font-bold mb-4">Assets (Past Hour)</h4>

              <%
                chart_cfg = %{
                 type: "line",
                 data: %{
                  datasets: account_type_datasets(ledger, :assets)
                 },
                options: %{
                  responsive: true,
                  elements: %{ point: %{ pointStyle: false } },
                  scales: %{
                    x: %{ type: "time", time: %{unit: "minute"}, suggestedMin: DateTime.to_iso8601(DateTime.add(DateTime.utc_now(), -1, :hour)) },
                    y: %{ stacked: true, suggestedMin: 0 }
                  }
                }
                }
              %>
              <canvas id="credits-history" phx-hook="Chart" data-config={Jason.encode!(chart_cfg)}></canvas>
          </div>

          <div class="bg-base-300 p-4 rounded">
            <h4 class="text-xl font-bold mb-4">Income (Past Hour)</h4>

            <.income_statement ledger={ledger} />
          </div>
          <div class="bg-base-300 p-4 rounded">
            <h4 class="text-xl font-bold mb-4">Balances</h4>

            <.trial_balance_table ledger={ledger} />
          </div>
        </div>
      </.async_result>
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
                <%= Money.to_string! amount, format: :accounting, currency_symbol: "", fractional_digits: 0 %>
              </td>
            </tr>
          <% end %>

          <tr>
            <th class="border-t">Total Revenue</th>
            <td class="text-right font-bold border-t">
              <%= Money.to_string! income.total_revenue, format: :accounting, currency_symbol: "", fractional_digits: 0 %>
            </td>
          </tr>

          <%= for %{account: %{name: name}, balance: amount} <- income.direct_costs do %>
            <tr>
              <td>
                <%= name %>
              </td>
              <td class="text-right">
                <%= Money.to_string! amount, format: :accounting, currency_symbol: "", fractional_digits: 0 %>
              </td>
            </tr>
          <% end %>

          <tr>
            <th class="border-t">Gross Profit</th>
            <td class="text-right font-bold border-t">
              <%= Money.to_string! income.gross_profit, format: :accounting, currency_symbol: "", fractional_digits: 0 %>
            </td>
          </tr>

          <%= for %{account: %{name: name}, balance: amount} <- income.expenses do %>
            <tr>
              <td>
                <%= name %>
              </td>
              <td class="text-right">
                <%= Money.to_string! amount, format: :accounting, currency_symbol: "", fractional_digits: 0 %>
              </td>
            </tr>
          <% end %>

          <tr>
            <th class="border-t">Net Earnings</th>
            <td class="text-right font-bold border-t">
              <%= Money.to_string! income.net_earnings, format: :accounting, currency_symbol: "", fractional_digits: 0 %>
            </td>
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
        balance = Ledger.balance(@ledger, @account_name)
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

  def mount(_params, %{"token" => token}, socket) do
    client = Client.new(token)
    {:ok, %{status: 200, body: agent_body}} = Agents.my_agent(client)
    PubSub.subscribe(@pubsub, "agent:#{agent_body["data"]["symbol"]}")
    callsign = agent_body["data"]["symbol"]

    socket =
      assign(socket, %{
        client: client,
        agent: AsyncResult.ok(agent_body["data"])
      })
      |> assign_async(:ledger, fn ->
        case LedgerServer.ledger(callsign) do
          {:ok, l} -> {:ok, %{ledger: l}}
          {:error, reason} -> {:error, reason}
        end
      end)
      |> assign_async(:agent_automaton, fn ->
        case AutomationServer.automaton(callsign) do
          {:ok, a} ->
            {:ok, %{agent_automaton: a}}

          {:error, _} ->
            {:ok, %{agent_automaton: nil}}
        end
      end)

    {:ok, socket}
  end

  def money_ratio(%Money{} = numerator, %Money{} = denominator) do
    {:XST, numerator_int, _, _} = Money.to_integer_exp(numerator)
    {:XST, denominator_int, _, _} = Money.to_integer_exp(denominator)

    if denominator_int == 0 do
      0.0
    else
      numerator_int / denominator_int
    end
  end

  def handle_info({:ledger_updated, ledger}, socket) do
    socket =
      assign(socket, :ledger, AsyncResult.ok(ledger))

    {:noreply, socket}
  end

  def handle_info(_, socket) do
    {:noreply, socket}
  end

  defp account_type_datasets(%Motocho.Ledger{} = ledger, type) do
    accounts =
      Enum.filter(ledger.accounts, fn {_id, account} ->
        account.type == type
      end)

    account_ids = Enum.map(accounts, fn {id, _acct} -> id end)

    journals =
      ledger.transactions
      |> Enum.sort_by(fn txn -> txn.date end, {:asc, DateTime})
      |> Enum.scan({nil, %{}}, fn txn, {_last_date, total_amounts} ->
        total_amounts =
          txn
          |> Journal.line_items()
          |> Enum.reduce(total_amounts, fn li, total_amounts ->
            case li.type do
              :debit ->
                update_in(
                  total_amounts,
                  [
                    Access.key(li.account_id, Money.zero(:XST))
                  ],
                  fn sum ->
                    Money.add!(sum, li.amount)
                  end
                )

              :credit ->
                update_in(
                  total_amounts,
                  [
                    Access.key(li.account_id, Money.zero(:XST))
                  ],
                  fn sum ->
                    Money.sub!(sum, li.amount)
                  end
                )
            end
          end)

        {txn, total_amounts}
      end)
      |> Enum.map(fn {txn, amounts} ->
        total_amounts =
          amounts
          |> Map.new(fn {acct_id, amount_money} ->
            amount_float =
              amount_money
              |> Money.to_decimal()
              |> Decimal.to_float()

            {acct_id, amount_float}
          end)

        {txn, total_amounts}
      end)
      |> Enum.filter(fn {txn, _amounts} ->
        one_hour_ago = DateTime.add(DateTime.utc_now(), -1, :hour)
        DateTime.after?(txn.date, one_hour_ago)
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
    |> Enum.filter(fn dataset ->
      dataset.label in ["Cash", "Merchandise"]
    end)
    |> Enum.sort_by(fn dataset ->
      Enum.find_index(["Cash", "Merchandise"], fn name -> dataset.label == name end)
    end)
  end
end
