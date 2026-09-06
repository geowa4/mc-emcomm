defmodule McEmcomm.MCP.Tools.Catalogs do
  @moduledoc """
  Dispatch table from the `kind` argument of the catalog tools to the
  Capabilities, Courses, and Certifications contexts, so the three catalogs
  share one list tool and one create/update pair.
  """

  alias McEmcomm.Capabilities
  alias McEmcomm.Certifications
  alias McEmcomm.Courses

  @kinds ~w(capability course certification)

  def kinds, do: @kinds

  def list("capability", opts), do: Capabilities.list_capabilities(opts)
  def list("course", opts), do: Courses.list_courses(opts)
  def list("certification", opts), do: Certifications.list_certifications(opts)

  def get("capability", id), do: Capabilities.get_capability(id)
  def get("course", id), do: Courses.get_course(id)
  def get("certification", id), do: Certifications.get_certification(id)

  def create("capability", attrs), do: Capabilities.create_capability(attrs)
  def create("course", attrs), do: Courses.create_course(attrs)
  def create("certification", attrs), do: Certifications.create_certification(attrs)

  def update("capability", item, attrs), do: Capabilities.update_capability(item, attrs)
  def update("course", item, attrs), do: Courses.update_course(item, attrs)
  def update("certification", item, attrs), do: Certifications.update_certification(item, attrs)

  @doc "The attribute keys a kind accepts (certifications carry two extra fields)."
  def fields("certification"),
    do: ~w(name code description active prerequisite_course_id requires_task_book)

  def fields(_kind), do: ~w(name code description active)
end
