defmodule McEmcommWeb.PageController do
  use McEmcommWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
