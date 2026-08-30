defmodule McEmcomm.Courses do
  @moduledoc "Admin catalog of courses and each member's recorded completions."

  import Ecto.Query, warn: false

  alias McEmcomm.Courses.Course
  alias McEmcomm.Courses.MemberCourse
  alias McEmcomm.Repo

  def list_courses(opts \\ []) do
    Course
    |> maybe_only_active(opts[:active_only])
    |> order_by([c], asc: c.name)
    |> Repo.all()
  end

  defp maybe_only_active(query, true), do: where(query, [c], c.active)
  defp maybe_only_active(query, _), do: query

  def get_course!(id), do: Repo.get!(Course, id)

  def change_course(%Course{} = course, attrs \\ %{}) do
    Course.changeset(course, attrs)
  end

  def create_course(attrs) do
    %Course{} |> Course.changeset(attrs) |> Repo.insert()
  end

  def update_course(%Course{} = course, attrs) do
    course |> Course.changeset(attrs) |> Repo.update()
  end

  def delete_course(%Course{} = course), do: Repo.delete(course)

  def list_member_courses(member_id) do
    MemberCourse
    |> where([mc], mc.member_id == ^member_id)
    |> preload(:course)
    |> Repo.all()
  end

  def get_member_course!(id), do: Repo.get!(MemberCourse, id) |> Repo.preload(:course)

  def change_member_course(%MemberCourse{} = mc, attrs \\ %{}) do
    MemberCourse.member_changeset(mc, attrs)
  end

  def add_member_course(attrs) do
    %MemberCourse{} |> MemberCourse.member_changeset(attrs) |> Repo.insert()
  end

  def update_member_course(%MemberCourse{} = mc, attrs) do
    mc |> MemberCourse.member_changeset(attrs) |> Repo.update()
  end

  def verify_member_course(%MemberCourse{} = mc, verified) when is_boolean(verified) do
    mc |> MemberCourse.verify_changeset(%{verified: verified}) |> Repo.update()
  end

  def remove_member_course(%MemberCourse{} = mc), do: Repo.delete(mc)
end
