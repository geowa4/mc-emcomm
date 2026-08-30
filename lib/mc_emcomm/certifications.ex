defmodule McEmcomm.Certifications do
  @moduledoc "Admin catalog of certifications and each member's recorded certifications."

  import Ecto.Query, warn: false

  alias McEmcomm.Certifications.Certification
  alias McEmcomm.Certifications.MemberCertification
  alias McEmcomm.Courses
  alias McEmcomm.Repo

  def list_certifications(opts \\ []) do
    Certification
    |> maybe_only_active(opts[:active_only])
    |> order_by([c], asc: c.name)
    |> preload(:prerequisite_course)
    |> Repo.all()
  end

  defp maybe_only_active(query, true), do: where(query, [c], c.active)
  defp maybe_only_active(query, _), do: query

  def get_certification!(id) do
    Certification |> Repo.get!(id) |> Repo.preload(:prerequisite_course)
  end

  def change_certification(%Certification{} = certification, attrs \\ %{}) do
    Certification.changeset(certification, attrs)
  end

  def create_certification(attrs) do
    %Certification{} |> Certification.changeset(attrs) |> Repo.insert()
  end

  def update_certification(%Certification{} = certification, attrs) do
    certification |> Certification.changeset(attrs) |> Repo.update()
  end

  def delete_certification(%Certification{} = certification), do: Repo.delete(certification)

  def list_member_certifications(member_id) do
    MemberCertification
    |> where([mc], mc.member_id == ^member_id)
    |> preload(certification: :prerequisite_course)
    |> Repo.all()
  end

  def get_member_certification!(id) do
    MemberCertification |> Repo.get!(id) |> Repo.preload(certification: :prerequisite_course)
  end

  def change_member_certification(%MemberCertification{} = mc, attrs \\ %{}) do
    MemberCertification.member_changeset(mc, attrs)
  end

  def add_member_certification(attrs) do
    %MemberCertification{} |> MemberCertification.member_changeset(attrs) |> Repo.insert()
  end

  def update_member_certification(%MemberCertification{} = mc, attrs) do
    mc |> MemberCertification.member_changeset(attrs) |> Repo.update()
  end

  def verify_member_certification(%MemberCertification{} = mc, verified)
      when is_boolean(verified) do
    mc |> MemberCertification.verify_changeset(%{verified: verified}) |> Repo.update()
  end

  def remove_member_certification(%MemberCertification{} = mc), do: Repo.delete(mc)

  @doc """
  Whether `member_id` has completed the certification's prerequisite course
  (per `member_courses.completed_on`). Returns `true` when there is no
  prerequisite. Used to display prerequisite status on the profile UI.
  """
  def prerequisite_met?(_member_id, %Certification{prerequisite_course_id: nil}), do: true

  def prerequisite_met?(member_id, %Certification{prerequisite_course_id: course_id}) do
    member_id
    |> Courses.list_member_courses()
    |> Enum.any?(fn mc -> mc.course_id == course_id and not is_nil(mc.completed_on) end)
  end
end
