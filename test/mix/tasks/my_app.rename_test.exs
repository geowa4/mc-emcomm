defmodule Mix.Tasks.MyApp.RenameTest do
  # Changes the working directory, so it must not run concurrently.
  use ExUnit.Case, async: false

  @task_source "lib/mix/tasks/my_app.rename.ex"
  @task_test "test/mix/tasks/my_app.rename_test.exs"

  setup do
    Mix.shell(Mix.Shell.Process)
    on_exit(fn -> Mix.shell(Mix.Shell.IO) end)

    tmp =
      Path.join(
        System.tmp_dir!(),
        "my_app_rename_#{System.unique_integer([:positive])}"
      )

    fixture(tmp, ".formatter.exs", ~s([inputs: ["{lib,test}/**/*.{ex,exs}"]]\n))
    # Deliberately mis-spaced: the task runs `mix format` after renaming.
    fixture(
      tmp,
      "lib/my_app/foo.ex",
      "defmodule MyApp.Foo do\n  alias   MyAppWeb.Endpoint\nend\n"
    )

    fixture(tmp, "lib/my_app/accounts/user.ex", "defmodule MyApp.Accounts.User do\nend\n")
    fixture(tmp, "lib/my_app_web/bar.ex", "defmodule MyAppWeb.Bar do\nend\n")
    fixture(tmp, "test/my_app/foo_test.exs", "MyApp.Foo\n")
    fixture(tmp, ".github/workflows/ci.yml", "DATABASE_URL: postgres://localhost/my_app_test\n")
    fixture(tmp, ".gitignore", "my_app-*.tar\n")
    fixture(tmp, "fly.toml", "app = \"my-app\"\nPHX_HOST = \"my-app.fly.dev\"\n")
    fixture(tmp, ".git/config", "[remote] url = git@github.com:acme/my_app.git\n")
    fixture(tmp, "deps/dep/lib/my_app_ref.ex", "MyApp\n")
    fixture(tmp, "_build/dev/lib/my_app/ebin/x", "MyApp\n")
    fixture(tmp, "priv/static/favicon.ico", <<0, 255, 0>>)
    fixture(tmp, "LICENSE", "MIT License\n")
    fixture(tmp, @task_source, File.read!(@task_source))
    fixture(tmp, @task_test, "defmodule Mix.Tasks.MyApp.RenameTest do\nend\n")

    on_exit(fn -> File.rm_rf!(tmp) end)
    {:ok, tmp: tmp}
  end

  test "renames contents and paths, skips build/vcs dirs, and deletes itself", %{tmp: tmp} do
    in_dir(tmp, fn ->
      Mix.Tasks.MyApp.Rename.run(["--otp", "acme_shop", "--module", "AcmeShop"])
    end)

    assert File.read!(Path.join(tmp, "lib/acme_shop/foo.ex")) ==
             "defmodule AcmeShop.Foo do\n  alias AcmeShopWeb.Endpoint\nend\n"

    assert File.read!(Path.join(tmp, "lib/acme_shop_web/bar.ex")) ==
             "defmodule AcmeShopWeb.Bar do\nend\n"

    assert File.read!(Path.join(tmp, "test/acme_shop/foo_test.exs")) == "AcmeShop.Foo\n"
    assert File.read!(Path.join(tmp, ".github/workflows/ci.yml")) =~ "acme_shop_test"
    assert File.read!(Path.join(tmp, ".gitignore")) == "acme_shop-*.tar\n"

    assert File.read!(Path.join(tmp, "fly.toml")) ==
             "app = \"acme-shop\"\nPHX_HOST = \"acme-shop.fly.dev\"\n"

    assert File.read!(Path.join(tmp, "LICENSE")) == "MIT License\n"

    # Untouched: VCS metadata, deps, build output, binary assets.
    assert File.read!(Path.join(tmp, ".git/config")) =~ "my_app.git"
    assert File.read!(Path.join(tmp, "deps/dep/lib/my_app_ref.ex")) == "MyApp\n"
    assert File.exists?(Path.join(tmp, "_build/dev/lib/my_app/ebin/x"))
    assert File.read!(Path.join(tmp, "priv/static/favicon.ico")) == <<0, 255, 0>>

    # Old directories are gone and the task removed itself.
    assert File.exists?(Path.join(tmp, "lib/acme_shop/accounts/user.ex"))
    refute File.exists?(Path.join(tmp, "lib/my_app/accounts"))
    refute File.exists?(Path.join(tmp, "lib/my_app"))
    refute File.exists?(Path.join(tmp, "lib/my_app_web"))
    refute File.exists?(Path.join(tmp, "test/my_app"))
    refute File.exists?(Path.join(tmp, @task_source))
    refute File.exists?(Path.join(tmp, @task_test))
    refute File.exists?(Path.join(tmp, "test/mix/tasks/acme_shop.rename_test.exs"))
    refute File.exists?(Path.join(tmp, "lib/mix/tasks/acme_shop.rename.ex"))

    assert_received {:mix_shell, :info, [msg]}
    assert msg =~ "Renamed to AcmeShop (acme_shop)"
  end

  test "validates its arguments", %{tmp: tmp} do
    in_dir(tmp, fn ->
      assert_raise Mix.Error, ~r/--otp .* is required/, fn ->
        Mix.Tasks.MyApp.Rename.run(["--module", "Acme"])
      end

      assert_raise Mix.Error, ~r/--module .* is required/, fn ->
        Mix.Tasks.MyApp.Rename.run(["--otp", "acme"])
      end

      assert_raise Mix.Error, ~r/must be snake_case/, fn ->
        Mix.Tasks.MyApp.Rename.run(["--otp", "Acme", "--module", "Acme"])
      end

      assert_raise Mix.Error, ~r/must be PascalCase/, fn ->
        Mix.Tasks.MyApp.Rename.run(["--otp", "acme", "--module", "acme"])
      end
    end)

    # Nothing was touched.
    assert File.exists?(Path.join(tmp, "lib/my_app/foo.ex"))
  end

  defp fixture(root, rel, contents) do
    path = Path.join(root, rel)
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, contents)
  end

  defp in_dir(dir, fun), do: File.cd!(dir, fun)
end
