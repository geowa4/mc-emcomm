defmodule McEmcomm.Accounts.UserEmail do
  @moduledoc """
  An additional email address a user has proven they own, beside the primary
  `users.email`. A row exists only once the address is confirmed: a pending
  address lives in its `add_email` token until then.

  Any of a user's addresses can be used to log in; account mail goes to the
  primary one.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  schema "users_emails" do
    field :email, :string
    belongs_to :user, McEmcomm.Accounts.User

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for an address the user asks to add. `user_id` is set on the
  struct by the caller, never cast.

  Only the shape is validated here. An address that belongs to somebody else
  is deliberately not an error: claiming it starts an account merge, and the
  form must answer the same way either way so it cannot be used to find out
  which addresses have accounts.
  """
  def changeset(user_email, attrs) do
    user_email
    |> cast(attrs, [:email])
    |> update_change(:email, &String.trim/1)
    |> validate_required([:email])
    |> validate_format(:email, ~r/^[^@,;\s]+@[^@,;\s]+$/,
      message: "must have the @ sign and no spaces"
    )
    |> validate_length(:email, max: 160)
    |> unique_constraint(:email)
    |> foreign_key_constraint(:user_id)
  end
end
