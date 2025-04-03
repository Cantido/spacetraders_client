defmodule SpacetradersClientWeb.TrialBalanceComponent do
  use SpacetradersClientWeb, :live_component

  alias SpacetradersClient.Game.Agent
  alias SpacetradersClient.Finance
  alias SpacetradersClient.Finance.Account
  alias SpacetradersClient.Repo

  alias SpacetradersClient.Cldr.Number

  def render(assigns) do
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
        <.ledger_account_row
          :for={{account, balance} <- @balances}
          account={account}
          balance={balance}
        />
      </tbody>

    </table>
    """
  end

  attr :account, Account, required: true
  attr :balance, :integer, required: true

  defp ledger_account_row(assigns) do
    ~H"""
    <tr>
      <td><%= @account.name %></td> <td class="text-right">
        <%= if @account.type in [:assets, :expenses] do %>
          <%= Number.to_string!(@balance, format: :accounting, fractional_digits: 0) %>
        <% end %>
      </td>

      <td class="text-right">
        <%= if @account.type not in [:assets, :expenses] do %>
          <%= Number.to_string!(@balance, format: :accounting, fractional_digits: 0) %>
        <% end %>
      </td>
    </tr>
    """
  end

  def update(assigns, socket) do
    agent_symbol = Map.fetch!(assigns, :agent_symbol)

    agent =
      Repo.get_by(Agent, symbol: agent_symbol)
      |> Repo.preload(:accounts)

    balances =
      Enum.map(agent.accounts, fn account ->
        {account, Finance.account_balance(account.id)}
      end)

    socket =
      socket
      |> assign(%{
        balances: balances
      })

    {:ok, socket}
  end
end
