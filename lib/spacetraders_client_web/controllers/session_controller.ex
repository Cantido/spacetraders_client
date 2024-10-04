defmodule SpacetradersClientWeb.SessionController do
  use SpacetradersClientWeb, :controller

  def index(conn, _params) do
    render(conn, :index, form: %{"token" => nil})
  end

  def log_in(conn, %{"token" => token}) do
    if token_valid?(token) do
      conn
      |> put_session(:token, token)
      |> redirect(to: ~p"/game")
    else
      conn
      |> render(:index, error_message: "That token is not valid")
    end
  end


  defp token_valid?(token) do
    client = SpacetradersClient.Client.new(token)

    {:ok, resp} = SpacetradersClient.Agents.my_agent(client)

    resp.status == 200
  end
end
