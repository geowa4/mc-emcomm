defmodule McEmcommWeb.PageController do
  use McEmcommWeb, :controller

  def home(conn, _params) do
    render(conn, :home, page_title: "Home")
  end
end
