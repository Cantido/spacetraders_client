defmodule SpacetradersClientWeb.RefuelModalComponent do
  use SpacetradersClientWeb, :html

  alias SpacetradersClient.Fleet

  attr :client, Tesla.Client, required: true
  attr :available_funds, :integer, required: true
  attr :fuel_price, :integer, required: true
  attr :ship, :map, required: true

  def modal(assigns) do
    ~H"""
    <dialog id="fuel_dialog" class="modal">
      <div class="modal-box">
        <div class="text-2xl font-bold mb-4">Purchase fuel</div>
        <div class="form-control">
          <label class="label cursor-pointer">
            <span class="label-text">Ship to refuel</span>
            <%= @ship["registration"]["name"] %>
            <%= @ship["fuel"]["current"] %>
            <%= @ship["fuel"]["capacity"] %>
          </label>
        </div>
        <div class="form-control">
          <label class="label cursor-pointer">
            <span class="label-text">Refuel to max capacity</span>
            <input type="radio" name="radio-10" class="radio" checked="checked" />
          </label>
        </div>
        <div class="form-control">
          <label class="label cursor-pointer">
            <span class="label-text">Buy a specific amount</span>
            <input type="radio" name="radio-10" class="radio" />
          </label>
        </div>
        <div class="w-full flex justify-center">
          <div class="w-1/2 mt-8 text-sm">
            <div class="flex justify-between">
              <span>Starting balance</span>
              <span><%= @available_funds %> &#8450;</span>
            </div>
            <div class="flex justify-between">
              <span>XX fuel units</span>
              <span>&minus; <%= @fuel_price / 100 %> &#8450;</span>
            </div>
            <div class="border-t flex justify-between">
              <span>Remaining balance</span>
              <span>234523 &#8450;</span>
            </div>

          </div>
        </div>
        <div class="modal-action mt-8">
          <form method="dialog">
            <button
              phx-click="purchase-fuel"
              phx-value-ship-symbol={@ship["symbol"]}
              class="btn btn-primary"
            >
              Purchase
            </button>
            <button class="btn">Close</button>
          </form>
        </div>
      </div>
    </dialog>
    """
  end

end
