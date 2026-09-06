defmodule McEmcomm.MCP.Tools.UpdateMyProfile do
  @moduledoc false
  use McEmcomm.MCP.Tool

  alias McEmcomm.MCP.Tool
  alias McEmcomm.MCP.Tools.GetMyProfile
  alias McEmcomm.Members
  alias McEmcomm.OAuth.Scopes

  @impl true
  def name, do: "update_my_profile"
  @impl true
  def title, do: "Update my profile"

  @impl true
  def description,
    do:
      "Updates the signed-in member's own profile: name, call sign, license class, home " <>
        "address and location, and emergency contact (name and phone go together). Only " <>
        "the fields given change; positions and admin status are not editable here."

  @impl true
  def input_schema do
    Schemas.object(%{
      "name" => Schemas.string("Name.", min: 1, max: 160),
      "call_sign" => Schemas.string("Call sign (upper-cased on save).", max: 16),
      "license_class" =>
        Schemas.string("License class.",
          enum: ~w(technician general amateur_extra advanced novice)
        ),
      "qth_address" => Schemas.string("Home address.", max: 500),
      "qth" => Schemas.point(),
      "emergency_contact_name" => Schemas.string("Emergency contact name.", max: 160),
      "emergency_contact_phone" => Schemas.string("Emergency contact phone.", max: 32),
      "emergency_contact_relation" => Schemas.string("Relationship.", max: 80)
    })
  end

  @impl true
  def output_schema, do: Schemas.profile()
  @impl true
  def annotations, do: Tool.write(idempotent: true)
  @impl true
  def required_scope, do: Scopes.member()
  @impl true
  def required_role, do: :member

  @impl true
  def run(args, context) do
    with {:ok, member} <- approved_member(context),
         attrs = attrs(args),
         {:ok, updated} <- Members.update_profile(member, attrs) do
      {:ok, GetMyProfile.profile(Members.get_member(updated.id), context.scope)}
    end
  end

  defp attrs(args) do
    attrs =
      take_attrs(args, ~w(name call_sign license_class qth_address emergency_contact_name
                          emergency_contact_phone emergency_contact_relation))

    case args["qth"] do
      nil -> attrs
      point -> Map.put(attrs, "qth_point", to_point(point))
    end
  end
end
