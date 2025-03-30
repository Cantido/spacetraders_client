defmodule SpacetradersClientWeb.CreditsLive do
  use SpacetradersClientWeb, :live_view

  alias Phoenix.LiveView.AsyncResult
  alias Phoenix.PubSub
  alias SpacetradersClient.Game.Agent
  alias SpacetradersClient.Finance
  alias SpacetradersClient.Finance.Account
  alias SpacetradersClient.Finance.Transaction
  alias SpacetradersClient.Cldr.Number
  alias SpacetradersClient.Repo

  import Ecto.Query, except: [update: 3]

  @pubsub SpacetradersClient.PubSub

  def render(assigns) do
    ~H"""
    <div class="p-4">
      <div class="stats mb-8 bg-base-300">
        <%= if @income_statement.total_revenue > 0 do %>
          <div class="stat">
            <div class="stat-title">Net profit margin</div>
            <div class="stat-value">
              {Float.round(
                money_ratio(@income_statement.net_earnings, @income_statement.total_revenue) * 100,
                1
              )}%
            </div>
            <div class="stat-desc">Past hour</div>
          </div>
        <% end %>

        <div class="stat">
          <div class="stat-title">Return on Assets</div>
          <div class="stat-value">
            {Float.round(
              money_ratio(@income_statement.net_earnings, @balance_sheet.total_assets) * 100,
              1
            )}%
          </div>
          <div class="stat-desc">Past hour; incl. fleet assets</div>
        </div>
      </div>

      <div class="flex flex-wrap gap-8 mb-4">
        <div class="bg-base-300 p-4 rounded basis-1/2">
          <h4 class="text-xl font-bold mb-4">Assets (Past Hour)</h4>

          <% chart_cfg = %{
            type: "line",
            data: %{
              datasets: assets_dataset(@agent_symbol)
            },
            options: %{
              responsive: true,
              elements: %{point: %{pointStyle: false}},
              scales: %{
                x: %{
                  type: "time",
                  time: %{unit: "minute"},
                  suggestedMin: DateTime.to_iso8601(DateTime.add(DateTime.utc_now(), -1, :hour))
                },
                y: %{stacked: true, suggestedMin: 0}
              }
            }
          } %>
          <div class="relative aspect-2/1">
            <canvas id="credits-history" phx-hook="Chart" data-config={Jason.encode!(chart_cfg)}>
            </canvas>
          </div>
        </div>

        <div class="flex-1 bg-base-300 p-4 rounded grow">
          <h4 class="text-xl font-bold mb-4">Income (Past Hour)</h4>

          <.income_statement income_statement={@income_statement} />
        </div>
        <div class="flex-1 bg-base-300 p-4 rounded grow">
          <h4 class="text-xl font-bold mb-4">Balances</h4>

          <.live_component
            module={SpacetradersClientWeb.TrialBalanceComponent}
            id={"trial-balance-#{@agent_symbol}"}
            agent_symbol={@agent_symbol}
          />
        </div>
      </div>

      <div class="bg-base-300 p-4 rounded">
        <h4 class="text-xl font-bold mb-4">Accounts</h4>

        <.radio_tablist name="transactions" class="tabs-lift">
          <:tab label="Cash" active={true}>
            <.live_component
              module={SpacetradersClientWeb.AccountEntriesComponent}
              id={"account-entries-#{@agent_symbol}-Cash"}
              account_id={Enum.at(@accounts, 0).id}
            />
          </:tab>
          <:tab label="Fleet">
            <.live_component
              module={SpacetradersClientWeb.AccountEntriesComponent}
              id={"account-entries-#{@agent_symbol}-Fleet"}
              account_id={Enum.at(@accounts, 1).id}
            />
          </:tab>
          <:tab label="Merchandise">
            <.live_component
              module={SpacetradersClientWeb.AccountEntriesComponent}
              id={"account-entries-#{@agent_symbol}-Merchandise"}
              account_id={Enum.at(@accounts, 2).id}
            />
          </:tab>
          <:tab label="Sales">
            <.live_component
              module={SpacetradersClientWeb.AccountEntriesComponent}
              id={"account-entries-#{@agent_symbol}-Sales"}
              account_id={Enum.at(@accounts, 3).id}
            />
          </:tab>
          <:tab label="Natural Resources">
            <.live_component
              module={SpacetradersClientWeb.AccountEntriesComponent}
              id={"account-entries-#{@agent_symbol}-Natural-Resources"}
              account_id={Enum.at(@accounts, 4).id}
            />
          </:tab>
          <:tab label="Starting Balances">
            <.live_component
              module={SpacetradersClientWeb.AccountEntriesComponent}
              id={"account-entries-#{@agent_symbol}-Starting-Balances"}
              account_id={Enum.at(@accounts, 5).id}
            />
          </:tab>
          <:tab label="Cost of Merchandise Sold">
            <.live_component
              module={SpacetradersClientWeb.AccountEntriesComponent}
              id={"account-entries-#{@agent_symbol}-Merch-Cost"}
              account_id={Enum.at(@accounts, 6).id}
            />
          </:tab>
          <:tab label="Construction Site Supply">
            <.live_component
              module={SpacetradersClientWeb.AccountEntriesComponent}
              id={"account-entries-#{@agent_symbol}-Site-Supply"}
              account_id={Enum.at(@accounts, 7).id}
            />
          </:tab>
          <:tab label="Fuel">
            <.live_component
              module={SpacetradersClientWeb.AccountEntriesComponent}
              id={"account-entries-#{@agent_symbol}-Fuel"}
              account_id={Enum.at(@accounts, 8).id}
            />
          </:tab>
        </.radio_tablist>
      </div>
    </div>
    """
  end

  def income_statement(assigns) do
    ~H"""
    <div>
      <table class="table table-sm">
        <tbody>
          <tr>
            <th>Revenue</th>
            <td></td>
          </tr>
          <%= for %{account: %{name: name}, balance: amount} <- @income_statement.revenues do %>
            <tr>
              <td>
                {name}
              </td>
              <td class="text-right">
                {Number.to_string!(amount, format: :accounting, fractional_digits: 0)}
              </td>
            </tr>
          <% end %>

          <tr>
            <th class="border-t">Total Revenue</th>
            <td class="text-right font-bold border-t">
              {Number.to_string!(@income_statement.total_revenue,
                format: :accounting,
                fractional_digits: 0
              )}
            </td>
          </tr>

          <%= for %{account: %{name: name}, balance: amount} <- @income_statement.direct_costs do %>
            <tr>
              <td>
                {name}
              </td>
              <td class="text-right">
                {Number.to_string!(amount, format: :accounting, fractional_digits: 0)}
              </td>
            </tr>
          <% end %>

          <tr>
            <th class="border-t">Gross Profit</th>
            <td class="text-right font-bold border-t">
              {Number.to_string!(@income_statement.gross_profit,
                format: :accounting,
                fractional_digits: 0
              )}
            </td>
          </tr>

          <%= for %{account: %{name: name}, balance: amount} <- @income_statement.expenses do %>
            <tr>
              <td>
                {name}
              </td>
              <td class="text-right">
                {Number.to_string!(amount, format: :accounting, fractional_digits: 0)}
              </td>
            </tr>
          <% end %>

          <tr>
            <th class="border-t">Net Earnings</th>
            <td class="text-right font-bold border-t">
              {Number.to_string!(@income_statement.net_earnings,
                format: :accounting,
                fractional_digits: 0
              )}
            </td>
          </tr>
        </tbody>
      </table>
    </div>
    """
  end

  defp account_txns(ledger, account_id) do
    ledger.transactions
    |> Enum.filter(fn txn ->
      Journal.affects_account?(txn, account_id)
    end)
    |> Enum.sort_by(fn txn -> txn.date end, :desc)
  end

  on_mount {SpacetradersClientWeb.GameLoader, :agent}

  def mount(_params, _session, socket) do
    PubSub.subscribe(@pubsub, "agent:#{socket.assigns.agent.result.symbol}")

    agent =
      Repo.get(Agent, socket.assigns.agent_symbol)
      |> Repo.preload(:accounts)

    income_statement =
      Finance.income_statement(
        socket.assigns.agent_symbol,
        DateTime.add(DateTime.utc_now(), -1, :hour),
        DateTime.utc_now()
      )

    balance_sheet = Finance.balance_sheet(socket.assigns.agent_symbol)

    socket =
      assign(socket, %{
        accounts: agent.accounts,
        app_section: :credits,
        income_statement: income_statement,
        balance_sheet: balance_sheet
      })

    {:ok, socket}
  end

  def handle_params(_params, _uri, socket) do
    {:noreply, socket}
  end

  def money_ratio(numerator, denominator) do
    if denominator == 0 do
      0.0
    else
      numerator / denominator
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

  defp assets_dataset(agent_symbol) do
    accounts_query =
      from a in Account,
        where: a.agent_symbol == ^agent_symbol,
        where: a.name in ["Cash", "Merchandise"],
        order_by: a.number

    account_ids_query =
      from a in accounts_query,
        select: a.id

    account_ids = Repo.all(account_ids_query)

    transactions =
      Repo.all(
        from tx in Transaction,
          join: li in assoc(tx, :line_items),
          where: li.account_id in subquery(account_ids_query),
          order_by: [asc: tx.timestamp],
          preload: [:line_items]
      )
      |> Enum.scan({nil, %{}}, fn txn, {_last_date, total_amounts} ->
        total_amounts =
          txn.line_items
          |> Enum.filter(fn li ->
            li.account_id in account_ids
          end)
          |> Enum.reduce(total_amounts, fn li, total_amounts ->
            case li.type do
              :debit ->
                update_in(
                  total_amounts,
                  [Access.key(to_string(li.account_id), 0)],
                  &(&1 + li.amount)
                )

              :credit ->
                update_in(
                  total_amounts,
                  [Access.key(to_string(li.account_id), 0)],
                  &(&1 - li.amount)
                )
            end
          end)

        {txn, total_amounts}
      end)
      |> Enum.map(fn {txn, amounts} ->
        %{x: txn.timestamp}
        |> Map.merge(amounts)
      end)

    Repo.all(accounts_query)
    |> Enum.map(fn account ->
      %{
        label: account.name,
        data: transactions,
        parsing: %{yAxisKey: to_string(account.id)},
        fill: true
      }
    end)
    |> dbg()
  end
end
