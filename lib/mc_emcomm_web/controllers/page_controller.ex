defmodule McEmcommWeb.PageController do
  use McEmcommWeb, :controller

  def home(conn, _params) do
    render(conn, :home,
      page_title: "Home",
      meta_description:
        "Monroe County ARES/RACES: licensed Amateur Radio volunteers providing emergency " <>
          "communications support to Monroe County, NY. Learn about us, train with us, or " <>
          "become a member.",
      active_net: McEmcomm.Net.latest_active_session()
    )
  end
end
