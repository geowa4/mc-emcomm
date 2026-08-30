[
  # Known Ecto.Multi + Dialyzer false positive on this OTP/Elixir/Ecto
  # combination: `Ecto.Multi.t()` embeds a `MapSet.t()` (itself `@opaque`),
  # and Dialyzer's opacity checker misflags passing the (correctly opaque)
  # Multi struct back into Multi.insert/2,3 or Multi.update/2,3 as a
  # "call_without_opaque" mismatch — even when the value comes straight from
  # `Ecto.Multi.new/0` via a bound variable, not a literal/matched struct.
  # Verified as a false positive: these three sites are exercised by
  # McEmcomm.MembersTest, McEmcomm.ExercisesTest, and
  # McEmcommWeb.UserLive.RegistrationTest, all passing.
  {"lib/mc_emcomm/exercises.ex", :call_without_opaque},
  {"lib/mc_emcomm/members.ex", :call_without_opaque},
  {"lib/mc_emcomm_web/live/user_live/registration.ex", :call_without_opaque}
]
