defmodule McEmcomm.Accounts.RecoveryCode do
  @moduledoc """
  Single-use backup codes for users with two-factor authentication enabled.

  Only a SHA-256 hash of each code is stored. The plaintext is shown to the
  user exactly once, when the batch is generated. SHA-256 is enough because
  the codes are 80-bit server-generated random values, not human-chosen
  passwords, so a slow key derivation function adds nothing against an
  offline attack and would make each login attempt expensive.
  """
  use Ecto.Schema

  @type t :: %__MODULE__{}

  @code_count 8
  @rand_size 10
  @hash_algorithm :sha256
  @group_size 4

  schema "users_recovery_codes" do
    field :hashed_code, :binary, redact: true
    field :used_at, :utc_datetime
    belongs_to :user, McEmcomm.Accounts.User

    timestamps(type: :utc_datetime, updated_at: false)
  end

  @doc "How many codes a batch contains."
  @spec code_count() :: pos_integer()
  def code_count, do: @code_count

  @doc """
  Generates one plaintext code, formatted as `xxxx-xxxx-xxxx-xxxx`.

  The alphabet is lowercase base32 (`a-z` and `2-7`), which has no
  visually ambiguous characters.
  """
  @spec generate() :: String.t()
  def generate do
    @rand_size
    |> :crypto.strong_rand_bytes()
    |> Base.encode32(case: :lower, padding: false)
    |> format()
  end

  @doc """
  Normalizes user input before hashing: lowercases it and strips dashes and
  whitespace, so `ABCD-EFGH ...` and `abcdefgh...` verify the same.
  """
  @spec normalize(String.t()) :: String.t()
  def normalize(code) when is_binary(code) do
    code
    |> String.downcase()
    |> String.replace(~r/[-\s]/, "")
  end

  @doc "Hashes a (raw or formatted) code the way it is stored."
  @spec hash(String.t()) :: binary()
  def hash(code) when is_binary(code) do
    :crypto.hash(@hash_algorithm, normalize(code))
  end

  @doc """
  Builds a fresh batch for `user`.

  Returns the plaintext codes to show the user together with the structs to
  insert.
  """
  @spec build_batch(McEmcomm.Accounts.User.t()) :: {[String.t()], [t()]}
  def build_batch(%McEmcomm.Accounts.User{id: user_id}) do
    codes = Enum.map(1..@code_count, fn _ -> generate() end)

    structs =
      Enum.map(codes, fn code ->
        %__MODULE__{user_id: user_id, hashed_code: hash(code)}
      end)

    {codes, structs}
  end

  defp format(raw) do
    raw
    |> String.graphemes()
    |> Enum.chunk_every(@group_size)
    |> Enum.map_join("-", &Enum.join/1)
  end
end
