defmodule McEmcommWeb.AppLive.Profile do
  use McEmcommWeb, :live_view

  alias McEmcomm.Capabilities
  alias McEmcomm.Certifications
  alias McEmcomm.Courses
  alias McEmcomm.Members
  alias McEmcomm.Members.Member
  alias McEmcomm.Storage
  alias McEmcommWeb.MapHelpers
  alias McEmcommWeb.ParamHelpers

  @impl true
  def mount(_params, _session, socket) do
    member = socket.assigns.current_scope.member

    socket =
      if member do
        assign_profile(socket, member)
      else
        socket
        |> put_flash(:error, "Only approved members have a profile.")
        |> push_navigate(to: ~p"/app")
      end

    # Each course/certification row gets its own upload config (named by
    # record id) rather than one shared name reused across every
    # <.live_file_input> — a single config rendered in multiple rows would
    # have them all mirror the same pending entry.
    socket =
      Enum.reduce(socket.assigns[:courses] || [], socket, fn course, socket ->
        allow_upload(socket, course_upload_name(course.id),
          accept: :any,
          max_entries: 1,
          external: &presign_entry/2
        )
      end)

    socket =
      Enum.reduce(socket.assigns[:certifications] || [], socket, fn cert, socket ->
        socket
        |> allow_upload(task_book_upload_name(cert.id),
          accept: :any,
          max_entries: 1,
          external: &presign_entry/2
        )
        |> allow_upload(certificate_upload_name(cert.id),
          accept: :any,
          max_entries: 1,
          external: &presign_entry/2
        )
      end)

    {:ok, socket}
  end

  defp course_upload_name(course_id), do: :"course_evidence_#{course_id}"
  defp task_book_upload_name(cert_id), do: :"task_book_#{cert_id}"
  defp certificate_upload_name(cert_id), do: :"certificate_#{cert_id}"

  defp assign_profile(socket, member) do
    assign(socket,
      page_title: "My Profile",
      member: member,
      form: to_form(Members.change_profile(member)),
      capabilities: Capabilities.list_capabilities(active_only: true),
      member_capabilities: Capabilities.list_member_capabilities(member.id),
      courses: Courses.list_courses(active_only: true),
      member_courses: Courses.list_member_courses(member.id),
      certifications: Certifications.list_certifications(active_only: true),
      member_certifications: Certifications.list_member_certifications(member.id),
      tile_url: MapHelpers.tile_url()
    )
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} active_net={@active_net}>
      <.header>My Profile</.header>

      <.form for={@form} id="profile-form" phx-change="validate" phx-submit="save" class="max-w-lg">
        <.input field={@form[:name]} label="Full name" required />
        <.input field={@form[:call_sign]} label="Call sign" />
        <.input
          field={@form[:license_class]}
          type="select"
          label="License class"
          prompt="Select one"
          options={Enum.map(Member.license_classes(), &{Phoenix.Naming.humanize(&1), &1})}
        />
        <.input field={@form[:qth_address]} label="QTH address" />

        <fieldset id="emergency-contact" class="mt-6">
          <legend class="text-lg font-semibold">Emergency contact</legend>
          <p class="text-sm text-base-content/60">
            Optional. Who should we reach if something happens to you during a deployment?
          </p>
          <.input field={@form[:emergency_contact_name]} label="Contact name" />
          <.input field={@form[:emergency_contact_phone]} type="tel" label="Contact phone" />
          <.input
            field={@form[:emergency_contact_relation]}
            label="Relation to you"
            placeholder="Spouse, parent, neighbor…"
          />
        </fieldset>

        <.button phx-disable-with="Saving..." class="btn btn-primary mt-4">Save profile</.button>
      </.form>

      <section id="qth-location" class="max-w-lg" aria-labelledby="qth-location-heading">
        <h2 id="qth-location-heading" class="text-lg font-semibold mt-8">QTH location</h2>
        <.map_picker
          id="qth-map"
          label="QTH location map"
          point={@member.qth_point}
          tile_url={@tile_url}
          on_submit="set_qth_point"
          instructions="Click the map to drop a pin, or enter the coordinates below. Either saves right away."
        />
      </section>

      <h2 class="text-lg font-semibold mt-8">Capabilities</h2>
      <ul class="list bg-base-100 rounded-box border border-base-300">
        <li :for={cap <- @capabilities} class="list-row items-center">
          <label for={"capability-#{cap.id}"} class="flex-1 cursor-pointer">{cap.name}</label>
          <input
            id={"capability-#{cap.id}"}
            type="checkbox"
            class="checkbox"
            checked={Enum.any?(@member_capabilities, &(&1.capability_id == cap.id))}
            phx-click="toggle_capability"
            phx-value-id={cap.id}
          />
        </li>
      </ul>

      <h2 class="text-lg font-semibold mt-8">Courses</h2>
      <ul class="list bg-base-100 rounded-box border border-base-300">
        <li :for={course <- @courses} class="list-row items-center flex-wrap">
          <div class="flex-1">
            {course.name}
            <span :if={mc = member_course(@member_courses, course.id)}>
              <span :if={mc.completed_on} class="badge badge-sm badge-success ml-2">
                Completed {mc.completed_on}
              </span>
              <span :if={mc.verified} class="badge badge-sm badge-info ml-1">Verified</span>
            </span>
          </div>
          <form
            id={"course-form-#{course.id}"}
            phx-submit="save_course"
            phx-value-course_id={course.id}
            class="flex flex-wrap gap-2 items-end"
            aria-label={"#{course.name} completion"}
          >
            <.input
              type="date"
              id={"course-completed-on-#{course.id}"}
              name="completed_on"
              label="Completed on"
              value={completed_on(@member_courses, course.id)}
            />
            <div class="fieldset mb-2">
              <label for={@uploads[course_upload_name(course.id)].ref} class="label mb-1">
                Evidence
              </label>
              <.live_file_input upload={@uploads[course_upload_name(course.id)]} />
            </div>
            <.button class="btn btn-sm btn-secondary">Save</.button>
          </form>
        </li>
      </ul>

      <h2 class="text-lg font-semibold mt-8">Certifications</h2>
      <ul class="list bg-base-100 rounded-box border border-base-300">
        <li :for={cert <- @certifications} class="list-row flex-col items-stretch">
          <div class="flex justify-between items-center">
            <div>
              <strong>{cert.name}</strong>
              <span :if={cert.prerequisite_course}>
                &middot; prerequisite: {cert.prerequisite_course.name}
                <span
                  :if={prerequisite_met?(@member_courses, cert)}
                  class="badge badge-sm badge-success ml-1"
                >met</span>
                <span
                  :if={!prerequisite_met?(@member_courses, cert)}
                  class="badge badge-sm badge-warning ml-1"
                >not yet</span>
              </span>
              <span :if={mc = member_certification(@member_certifications, cert.id)}>
                <span :if={mc.verified} class="badge badge-sm badge-info ml-1">Verified</span>
              </span>
            </div>
          </div>
          <form
            id={"certification-form-#{cert.id}"}
            phx-submit="save_certification"
            phx-value-certification_id={cert.id}
            class="flex gap-2 items-end flex-wrap mt-2"
            aria-label={"#{cert.name} certification"}
          >
            <.input
              type="date"
              id={"certification-issued-on-#{cert.id}"}
              name="issued_on"
              label="Issued on"
              value={cert_field(@member_certifications, cert.id, :issued_on)}
            />
            <div class="fieldset mb-2">
              <label for={@uploads[task_book_upload_name(cert.id)].ref} class="label mb-1">
                Task book
              </label>
              <.live_file_input upload={@uploads[task_book_upload_name(cert.id)]} />
            </div>
            <div class="fieldset mb-2">
              <label for={@uploads[certificate_upload_name(cert.id)].ref} class="label mb-1">
                Certificate
              </label>
              <.live_file_input upload={@uploads[certificate_upload_name(cert.id)]} />
            </div>
            <.button class="btn btn-sm btn-secondary">Save</.button>
          </form>
        </li>
      </ul>
    </Layouts.app>
    """
  end

  defp member_course(member_courses, course_id),
    do: Enum.find(member_courses, &(&1.course_id == course_id))

  defp completed_on(member_courses, course_id),
    do:
      member_course(member_courses, course_id) &&
        member_course(member_courses, course_id).completed_on

  defp prerequisite_met?(_member_courses, %{prerequisite_course_id: nil}), do: true

  defp prerequisite_met?(member_courses, %{prerequisite_course_id: course_id}) do
    Enum.any?(member_courses, &(&1.course_id == course_id and not is_nil(&1.completed_on)))
  end

  defp member_certification(member_certifications, cert_id),
    do: Enum.find(member_certifications, &(&1.certification_id == cert_id))

  defp cert_field(member_certifications, cert_id, field) do
    case member_certification(member_certifications, cert_id) do
      nil -> nil
      mc -> Map.get(mc, field)
    end
  end

  @impl true
  def handle_event("validate", %{"member" => params}, socket) do
    form =
      socket.assigns.member
      |> Members.change_profile(params)
      |> Map.put(:action, :validate)
      |> to_form()

    {:noreply, assign(socket, form: form)}
  end

  def handle_event("point_selected", %{"lat" => lat, "lng" => lng}, socket) do
    save_qth_point(socket, MapHelpers.point(lat, lng))
  end

  # The typed-coordinates alternative to clicking the map.
  def handle_event("set_qth_point", params, socket) do
    case MapHelpers.parse_coordinates(params) do
      {:ok, point} -> save_qth_point(socket, point)
      :error -> {:noreply, put_flash(socket, :error, MapHelpers.invalid_coordinates_message())}
    end
  end

  def handle_event("save", %{"member" => params}, socket) do
    case Members.update_profile(socket.assigns.member, params) do
      {:ok, member} ->
        {:noreply,
         socket
         |> put_flash(:info, "Profile updated.")
         |> assign(member: member, form: to_form(Members.change_profile(member)))}

      {:error, changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  def handle_event("toggle_capability", %{"id" => id}, socket) do
    case ParamHelpers.known_id(socket.assigns.capabilities, id) do
      nil -> {:noreply, socket}
      capability_id -> toggle_capability(socket, capability_id)
    end
  end

  # The id is checked against the courses this socket rendered before it is
  # used: `course_upload_name/1` interpolates it into an atom, so an arbitrary
  # id would both create atoms without bound and raise on an unknown upload.
  def handle_event("save_course", %{"course_id" => course_id} = params, socket) do
    case ParamHelpers.known_id(socket.assigns.courses, course_id) do
      nil -> {:noreply, socket}
      course_id -> save_course(socket, course_id, params)
    end
  end

  def handle_event("save_certification", %{"certification_id" => cert_id} = params, socket) do
    case ParamHelpers.known_id(socket.assigns.certifications, cert_id) do
      nil -> {:noreply, socket}
      cert_id -> save_certification(socket, cert_id, params)
    end
  end

  defp toggle_capability(socket, capability_id) do
    member = socket.assigns.member

    case Enum.find(socket.assigns.member_capabilities, &(&1.capability_id == capability_id)) do
      nil ->
        Capabilities.add_member_capability(%{member_id: member.id, capability_id: capability_id})

      mc ->
        Capabilities.remove_member_capability(mc)
    end

    {:noreply,
     assign(socket, member_capabilities: Capabilities.list_member_capabilities(member.id))}
  end

  defp save_course(socket, course_id, params) do
    member = socket.assigns.member

    evidence =
      consume_uploaded_entries(socket, course_upload_name(course_id), fn %{key: key}, entry ->
        {:ok,
         %{
           evidence_key: key,
           evidence_filename: entry.client_name,
           evidence_content_type: entry.client_type
         }}
      end)
      |> List.first() || %{}

    attrs =
      %{
        member_id: member.id,
        course_id: course_id,
        completed_on: blank_to_nil(params["completed_on"])
      }
      |> Map.merge(evidence)

    result =
      case member_course(socket.assigns.member_courses, course_id) do
        nil -> Courses.add_member_course(attrs)
        mc -> Courses.update_member_course(mc, attrs)
      end

    case result do
      {:ok, _} ->
        {:noreply, assign(socket, member_courses: Courses.list_member_courses(member.id))}

      {:error, changeset} ->
        {:noreply, put_flash(socket, :error, "Course error: #{inspect(changeset.errors)}")}
    end
  end

  defp save_certification(socket, cert_id, params) do
    member = socket.assigns.member

    task_book =
      consume_uploaded_entries(socket, task_book_upload_name(cert_id), fn %{key: key}, entry ->
        {:ok,
         %{
           task_book_key: key,
           task_book_filename: entry.client_name,
           task_book_content_type: entry.client_type
         }}
      end)
      |> List.first() || %{}

    certificate =
      consume_uploaded_entries(socket, certificate_upload_name(cert_id), fn %{key: key}, entry ->
        {:ok,
         %{
           certificate_key: key,
           certificate_filename: entry.client_name,
           certificate_content_type: entry.client_type
         }}
      end)
      |> List.first() || %{}

    attrs =
      %{
        member_id: member.id,
        certification_id: cert_id,
        issued_on: blank_to_nil(params["issued_on"])
      }
      |> Map.merge(task_book)
      |> Map.merge(certificate)

    result =
      case member_certification(socket.assigns.member_certifications, cert_id) do
        nil -> Certifications.add_member_certification(attrs)
        mc -> Certifications.update_member_certification(mc, attrs)
      end

    case result do
      {:ok, _} ->
        {:noreply,
         assign(socket,
           member_certifications: Certifications.list_member_certifications(member.id)
         )}

      {:error, changeset} ->
        {:noreply, put_flash(socket, :error, "Certification error: #{inspect(changeset.errors)}")}
    end
  end

  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value

  defp presign_entry(entry, socket) do
    key = Storage.build_key("member-uploads", entry.client_name)
    presigned = Storage.presign_upload(key, entry.client_type)
    meta = %{uploader: "S3", key: key, url: presigned.url, fields: presigned.fields}
    {:ok, meta, socket}
  end

  defp save_qth_point(socket, point) do
    case Members.update_profile(socket.assigns.member, %{"qth_point" => point}) do
      {:ok, member} ->
        {:noreply,
         socket
         |> assign(member: member, form: to_form(Members.change_profile(member)))
         |> MapHelpers.push_point("qth-map", point)}

      {:error, changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end
end
