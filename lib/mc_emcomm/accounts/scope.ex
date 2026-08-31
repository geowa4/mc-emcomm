defmodule McEmcomm.Accounts.Scope do
  @moduledoc """
  Defines the scope of the caller to be used throughout the app.

  The `McEmcomm.Accounts.Scope` allows public interfaces to receive
  information about the caller, such as if the call is initiated from an
  end-user, and if so, which user. Additionally, such a scope can carry fields
  such as "super user" or other privileges for use in authorization checks,
  or to ensure specific code paths can only be accessed for a given scope.

  It is useful for logging as well as for scoping pubsub subscriptions and
  broadcasts when a caller subscribes to an interface or performs a particular
  action.

  Feel free to extend the fields on this struct to fit the needs of
  growing application requirements.
  """

  alias McEmcomm.Accounts.User
  alias McEmcomm.Members
  alias McEmcomm.Members.Member

  defstruct user: nil, member: nil, position_admin: false

  @type t :: %__MODULE__{
          user: User.t() | nil,
          member: Member.t() | nil,
          position_admin: boolean()
        }

  @doc """
  Creates a scope for the given user, loading their member profile (if any)
  so `member?/1` and `admin?/1` don't require a separate query at every
  call site.

  Returns nil if no user is given.
  """
  @spec for_user(User.t()) :: t()
  @spec for_user(nil) :: nil
  def for_user(%User{} = user) do
    member = Members.get_member_by_user_id(user.id)
    %__MODULE__{user: user, member: member, position_admin: position_admin?(member)}
  end

  def for_user(nil), do: nil

  # Only approved members can act on a position's admin grant — a holder
  # whose membership is later made inactive loses admin access even though
  # they still show as holding the position.
  defp position_admin?(%Member{id: id, status: :approved}), do: Members.holds_admin_position?(id)
  defp position_admin?(_member), do: false

  @doc "True when the scope's user is an approved member."
  @spec approved_member?(t() | nil) :: boolean()
  def approved_member?(%__MODULE__{member: %Member{status: :approved}}), do: true
  def approved_member?(_scope), do: false

  @doc """
  True when the scope's user has the admin flag, or is an approved member
  holding a leadership position that grants admin.
  """
  @spec admin?(t() | nil) :: boolean()
  def admin?(%__MODULE__{user: %User{is_admin: true}}), do: true
  def admin?(%__MODULE__{position_admin: true}), do: true
  def admin?(_scope), do: false
end
