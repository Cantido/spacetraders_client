defmodule SpacetradersClientWeb.AccountEntriesComponent do
  use SpacetradersClientWeb, :live_component

  alias SpacetradersClient.Finance
  alias SpacetradersClient.Finance.Account
  alias SpacetradersClient.Finance.TransactionLineItem
  alias SpacetradersClient.Repo
  alias SpacetradersClient.Cldr.Number

  import Ecto.Query, except: [update: 3]

  attr :class, :string, default: nil

  def render(assigns) do
    ~H"""
    <div>
      <.live_component
        module={SpacetradersClientWeb.DataTableComponent}
        id={"transactions-#{@account_id}"}
        class={["table-zebra table-sm bg-base-100", @class]}
        initial_sort_key={:timestamp}
        initial_sort_direction={:desc}
        rows={@line_items}
      >
        <:column :let={li} label="Timestamp" class="w-52" key={:timestamp} sorter={DateTime}>
          <time datetime={DateTime.to_iso8601(li.timestamp)}>
            {SpacetradersClient.Cldr.DateTime.to_string!(li.timestamp)}
          </time>
        </:column>
        <:column :let={li} key={:description} label="Description">
          {li.description}
        </:column>
        <:column :let={li} key={:debit_amount} label="Debit" class="text-right w-28">
          <div :if={li.type == :debit}>
            {Number.to_string!(li.amount, format: :accounting, fractional_digits: 0)}
          </div>
        </:column>

        <:column :let={li} key={:credit_amount} label="Credit" class="text-right w-28">
          <div :if={li.type == :credit}>
            {Number.to_string!(li.amount, format: :accounting, fractional_digits: 0)}
          </div>
        </:column>

        <:footer>
          <tr>
            <th class="border-t"></th>
            <th class="border-t">Total</th>
            <td class="text-right border-t">
              {Number.to_string!(@debit_balance, format: :accounting, fractional_digits: 0)}
            </td>
            <td class="text-right border-t">
              {Number.to_string!(@credit_balance, format: :accounting, fractional_digits: 0)}
            </td>
          </tr>

          <tr>
            <th></th>
            <th>Balance</th>
            <%= if @balance >= 0 do %>
              <td class="text-right border-t">
                {Number.to_string!(@balance, format: :accounting, fractional_digits: 0)}
              </td>
              <td class="border-t"></td>
            <% else %>
              <td class="border-t"></td>
              <td class="text-right border-t">
                {Number.to_string!(-@balance, format: :accounting, fractional_digits: 0)}
              </td>
            <% end %>
          </tr>
        </:footer>
      </.live_component>
    </div>
    """
  end

  def mount(socket) do
    {:ok, socket}
  end

  def update(assigns, socket) do
    account_id = Map.fetch!(assigns, :account_id)

    line_items =
      Repo.all(
        from(li in TransactionLineItem,
          join: tx in assoc(li, :transaction),
          join: acc in assoc(li, :account),
          join: ag in assoc(acc, :agent),
          where: acc.id == ^account_id,
          select: map(li, [:description, :amount, :type]),
          select_merge: %{timestamp: tx.timestamp}
        )
      )

    debit_balance = Finance.debit_balance(account_id)
    credit_balance = Finance.credit_balance(account_id)

    account = Repo.get(Account, account_id)

    balance =
      case account.type do
        :assets -> debit_balance - credit_balance
        :liabilities -> credit_balance - debit_balance
        :equity -> credit_balance - debit_balance
        :revenue -> credit_balance - debit_balance
        :expenses -> debit_balance - credit_balance
      end

    socket =
      socket
      |> assign(%{
        account_id: account_id,
        line_items: line_items,
        debit_balance: debit_balance,
        credit_balance: credit_balance,
        balance: balance
      })

    {:ok, socket}
  end
end
