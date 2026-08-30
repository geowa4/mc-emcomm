defmodule MyAppWeb.ErrorJSONTest do
  use ExUnit.Case, async: true

  alias MyAppWeb.ErrorJSON

  test "renders the status message as an error detail" do
    assert ErrorJSON.render("404.json", %{}) == %{errors: %{detail: "Not Found"}}
    assert ErrorJSON.render("500.json", %{}) == %{errors: %{detail: "Internal Server Error"}}
  end
end
