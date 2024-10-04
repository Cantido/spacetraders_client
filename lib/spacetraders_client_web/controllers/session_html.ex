defmodule SpacetradersClientWeb.SessionHTML do
  use SpacetradersClientWeb, :html

  embed_templates "session_html/*"

  attr :error_message, :string, default: nil

  def index(assigns)
end
