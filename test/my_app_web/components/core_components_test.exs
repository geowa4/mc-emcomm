defmodule MyAppWeb.CoreComponentsTest do
  use ExUnit.Case, async: true

  import Phoenix.Component
  import Phoenix.LiveViewTest

  alias MyAppWeb.CoreComponents
  alias Phoenix.LiveView.LiveStream

  defp parse(template), do: LazyHTML.from_fragment(rendered_to_string(template))

  defp count(lazy, selector), do: lazy |> LazyHTML.query(selector) |> Enum.count()

  describe "button/1" do
    test "renders a link when given a navigation attribute" do
      assigns = %{}

      html =
        parse(~H"""
        <CoreComponents.button navigate="/inbox">Inbox</CoreComponents.button>
        <CoreComponents.button href="/docs">Docs</CoreComponents.button>
        <CoreComponents.button patch="/inbox?page=2">Next</CoreComponents.button>
        """)

      assert count(html, "a") == 3
      assert count(html, "button") == 0

      assert LazyHTML.attribute(LazyHTML.query(html, "a"), "href") == [
               "/inbox",
               "/docs",
               "/inbox?page=2"
             ]
    end

    test "renders a button otherwise" do
      assigns = %{}

      html =
        parse(~H"""
        <CoreComponents.button variant="primary" phx-click="go">Go</CoreComponents.button>
        """)

      assert count(html, "button.btn-primary") == 1
    end
  end

  describe "input/1" do
    test "hidden inputs render only the input" do
      assigns = %{}

      html =
        parse(~H"""
        <CoreComponents.input type="hidden" name="token" value="abc" />
        """)

      assert LazyHTML.attribute(LazyHTML.query(html, "input[type=hidden]"), "value") == ["abc"]
      assert count(html, "label") == 0
    end

    test "checkbox inputs derive checked from the value and show errors" do
      assigns = %{}

      html =
        parse(~H"""
        <CoreComponents.input
          type="checkbox"
          id="opt-in"
          name="opt_in"
          value="true"
          label="Opt in"
          errors={["is required"]}
        />
        """)

      assert count(html, "input[type=hidden][name=opt_in][value=false]") == 1
      assert count(html, "input[type=checkbox]#opt-in[checked]") == 1
      assert LazyHTML.text(LazyHTML.query(html, "p")) =~ "is required"
    end

    test "checkbox inputs honour an explicit checked flag" do
      assigns = %{}

      html =
        parse(~H"""
        <CoreComponents.input type="checkbox" name="flag" value="true" checked={false} />
        """)

      assert count(html, "input[type=checkbox][checked]") == 0
    end

    test "select inputs render the prompt and options with the current value selected" do
      assigns = %{}

      html =
        parse(~H"""
        <CoreComponents.input
          type="select"
          id="role"
          name="role"
          label="Role"
          prompt="Choose"
          options={[Admin: "admin", User: "user"]}
          value="user"
          errors={["is invalid"]}
        />
        """)

      assert count(html, "select#role.select-error") == 1
      assert count(html, "option") == 3
      assert LazyHTML.attribute(LazyHTML.query(html, "option[selected]"), "value") == ["user"]
      assert LazyHTML.text(LazyHTML.query(html, "option[value='']")) == "Choose"
    end

    test "textarea inputs render the value as content" do
      assigns = %{}

      html =
        parse(~H"""
        <CoreComponents.input type="textarea" id="bio" name="bio" label="Bio" value="hello" rows="3" />
        """)

      textarea = LazyHTML.query(html, "textarea#bio")
      assert LazyHTML.text(textarea) == "hello"
      assert LazyHTML.attribute(textarea, "rows") == ["3"]
      assert count(html, "textarea.textarea-error") == 0
    end

    test "form fields supply id, name, value and errors once the input was used" do
      form =
        {%{"email" => "nope"}, %{email: :string}}
        |> Ecto.Changeset.cast(%{"email" => "nope"}, [:email])
        |> Ecto.Changeset.add_error(:email, "is invalid")
        |> Map.put(:action, :validate)
        |> to_form(as: :user)

      assigns = %{form: form}

      html =
        parse(~H"""
        <CoreComponents.input field={@form[:email]} type="email" label="Email" />
        """)

      assert count(html, "input#user_email[name='user[email]'][value=nope].input-error") == 1
      assert LazyHTML.text(LazyHTML.query(html, "p")) =~ "is invalid"
    end
  end

  describe "table/1" do
    test "renders columns, rows, actions, and row clicks" do
      assigns = %{rows: [%{id: 1, name: "Ada"}, %{id: 2, name: "Grace"}]}

      html =
        parse(~H"""
        <CoreComponents.table id="users" rows={@rows} row_click={&"select-#{&1.id}"}>
          <:col :let={user} label="Name">{user.name}</:col>
          <:col :let={user} label="ID">{user.id}</:col>
          <:action :let={user}>
            <a href={"/users/#{user.id}"}>Edit</a>
          </:action>
        </CoreComponents.table>
        """)

      assert count(html, "thead th") == 3
      assert count(html, "tbody#users tr") == 2
      assert count(html, "td.hover\\:cursor-pointer[phx-click=select-1]") == 2

      assert LazyHTML.attribute(LazyHTML.query(html, "tbody a"), "href") == [
               "/users/1",
               "/users/2"
             ]

      refute LazyHTML.query(html, "tbody") |> LazyHTML.attribute("phx-update") |> Enum.any?()
    end

    test "streams derive row ids and mark the body as a stream container" do
      stream = LiveStream.new(:users, make_ref(), [%{id: 7, name: "Ada"}], [])
      assigns = %{rows: stream}

      html =
        parse(~H"""
        <CoreComponents.table id="users" rows={@rows}>
          <:col :let={{_id, user}} label="Name">{user.name}</:col>
        </CoreComponents.table>
        """)

      assert LazyHTML.attribute(LazyHTML.query(html, "tbody#users"), "phx-update") == ["stream"]
      assert LazyHTML.attribute(LazyHTML.query(html, "tbody tr"), "id") == ["users-7"]
      assert count(html, "thead th") == 1
    end
  end

  describe "list/1" do
    test "renders one row per item with its title" do
      assigns = %{}

      html =
        parse(~H"""
        <CoreComponents.list>
          <:item title="Title">Hello</:item>
          <:item title="Views">42</:item>
        </CoreComponents.list>
        """)

      assert count(html, "li.list-row") == 2
      assert LazyHTML.text(LazyHTML.query(html, "li:first-child .font-bold")) == "Title"
      assert LazyHTML.text(LazyHTML.query(html, "li:last-child")) =~ "42"
    end
  end

  describe "translate_errors/2" do
    test "translates the errors for one field, interpolating bindings" do
      errors = [
        name: {"should be at least %{count} character(s)", count: 3},
        email: {"is invalid", []},
        name: {"can't be blank", []}
      ]

      assert CoreComponents.translate_errors(errors, :name) ==
               ["should be at least 3 character(s)", "can't be blank"]

      assert CoreComponents.translate_errors(errors, :age) == []
    end
  end
end
