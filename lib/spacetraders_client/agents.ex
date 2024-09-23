defmodule SpacetradersClient.Agents do
  def my_agent(client) do
    Tesla.get(client, "/v2/my/agent")
  end

  def list_agents(client) do
    Tesla.get(client, "/v2/agents")
  end

  def get_agent(client, agent_symbol) do
    Tesla.get(client, "/v2/agents/#{agent_symbol}")
  end
end
