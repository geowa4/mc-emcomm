defmodule McEmcommWeb.PageController do
  use McEmcommWeb, :controller

  def home(conn, _params) do
    render(conn, :home, page_title: "Home", active_net: McEmcomm.Net.latest_active_session())
  end
end
