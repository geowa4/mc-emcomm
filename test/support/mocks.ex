# Mox mocks are defined here (compiled with test/support) rather than in
# test_helper.exs so that `Application.compile_env`-based dispatch in lib/ sees
# the module at compile time and `compile --warnings-as-errors` stays clean.
Mox.defmock(MyApp.ResendMock, for: MyApp.Resend.Client)
