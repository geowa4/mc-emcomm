defmodule MyAppWeb.ErrorHTMLTest do
  use ExUnit.Case, async: true

  alias MyAppWeb.ErrorHTML

  test "renders the status message for the template" do
    assert ErrorHTML.render("404.html", []) == "Not Found"
    assert ErrorHTML.render("500.html", []) == "Internal Server Error"
  end
end
