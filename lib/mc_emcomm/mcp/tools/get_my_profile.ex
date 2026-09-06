defmodule McEmcomm.MCP.Tools.GetMyProfile do
  @moduledoc false
  use McEmcomm.MCP.Tool

  alias McEmcomm.Accounts.Scope
  alias McEmcomm.Capabilities
  alias McEmcomm.Certifications
  alias McEmcomm.Courses
  alias McEmcomm.MCP.Tool
  alias McEmcomm.MCP.Tools.Present
  alias McEmcomm.Members
  alias McEmcomm.OAuth.Scopes

  @impl true
  def name, do: "get_my_profile"
  @impl true
  def title, do: "Get my profile"

  @impl true
  def description,
    do:
      "Returns the signed-in member's own profile, training records, positions, and admin status."

  @impl true
  def input_schema, do: Schemas.no_arguments()
  @impl true
  def output_schema, do: Schemas.profile()
  @impl true
  def annotations, do: Tool.read_only()
  @impl true
  def required_scope, do: Scopes.member()
  @impl true
  def required_role, do: :member

  @impl true
  def run(_args, context) do
    case context.scope.member do
      nil ->
        {:error, "Your account has no member profile; register one on the website first."}

      member ->
        member = Members.get_member(member.id)
        {:ok, profile(member, context.scope)}
    end
  end

  @doc false
  def profile(member, scope) do
    %{
      "member_id" => member.id,
      "name" => member.name,
      "call_sign" => member.call_sign,
      "status" => Atom.to_string(member.status),
      "license_class" => member.license_class && Atom.to_string(member.license_class),
      "qth_address" => member.qth_address,
      "qth" => Present.point(member.qth_point),
      "emergency_contact" => Present.emergency_contact(member),
      "positions" => Enum.map(member.positions, & &1.name),
      "admin" => Scope.admin?(scope),
      "capabilities" =>
        member.id
        |> Capabilities.list_member_capabilities()
        |> Enum.map(&%{"id" => &1.capability_id, "name" => &1.capability.name}),
      "courses" =>
        member.id
        |> Courses.list_member_courses()
        |> Enum.map(
          &%{
            "course_id" => &1.course_id,
            "name" => &1.course.name,
            "completed_on" => Present.date(&1.completed_on),
            "verified" => &1.verified
          }
        ),
      "certifications" =>
        member.id
        |> Certifications.list_member_certifications()
        |> Enum.map(
          &%{
            "certification_id" => &1.certification_id,
            "name" => &1.certification.name,
            "issued_on" => Present.date(&1.issued_on),
            "expires_on" => Present.date(&1.expires_on),
            "verified" => &1.verified
          }
        )
    }
  end
end
