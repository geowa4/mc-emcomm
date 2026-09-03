defmodule McEmcommWeb.PublicLive.Training do
  use McEmcommWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: "Training",
       meta_description:
         "Recommended FEMA Independent Study courses and ARRL emergency communications " <>
           "training for Monroe County ARES/RACES members and interested operators."
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} active_net={@active_net}>
      <.header>Training</.header>

      <p>
        Continuous training is essential for effective emergency communications. We recommend
        the following courses for all members to enhance their skills and preparedness.
      </p>

      <h2 class="text-xl font-semibold mt-6">FEMA Independent Study Courses</h2>
      <p>
        These courses provide essential knowledge for working within the incident command structure during emergencies:
      </p>
      <ul class="list-disc list-inside space-y-1">
        <li>
          <a
            class="link"
            href="https://training.fema.gov/is/courseoverview.aspx?code=IS-100.c"
            target="_blank"
            rel="noopener"
          >
            IS-100.C: Introduction to the Incident Command System <.new_tab_note />
          </a>
          — learn the fundamentals of ICS for effective emergency response coordination.
        </li>
        <li>
          <a
            class="link"
            href="https://training.fema.gov/is/courseoverview.aspx?code=IS-200.c"
            target="_blank"
            rel="noopener"
          >
            IS-200.C: Basic Incident Command System for Initial Response <.new_tab_note />
          </a>
          — build on ICS basics with skills for initial response operations.
        </li>
        <li>
          <a
            class="link"
            href="https://training.fema.gov/is/courseoverview.aspx?code=IS-700.b"
            target="_blank"
            rel="noopener"
          >
            IS-700.B: An Introduction to the National Incident Management System <.new_tab_note />
          </a>
          — understand NIMS and its role in national emergency management.
        </li>
        <li>
          <a
            class="link"
            href="https://training.fema.gov/is/courseoverview.aspx?code=IS-800.d"
            target="_blank"
            rel="noopener"
          >
            IS-800.D: National Response Framework, An Introduction <.new_tab_note />
          </a>
          — learn about the NRF and how communities respond to disasters.
        </li>
      </ul>

      <h2 class="text-xl font-semibold mt-6">Amateur Radio Emergency Communications</h2>
      <ul class="list-disc list-inside space-y-1">
        <li>
          <a
            class="link"
            href="http://www.arrl.org/emergency-communications-training"
            target="_blank"
            rel="noopener"
          >
            ARRL Emergency Communications Training <.new_tab_note />
          </a>
          — ARRL's comprehensive emergency operations courses, including integrated FEMA and
          Skywarn training.
        </li>
        <li>
          <a class="link" href="https://www.auxcommusa.org/training" target="_blank" rel="noopener">
            AuxComm Training <.new_tab_note />
          </a>
          — auxiliary communications training program for emergency communicators.
        </li>
      </ul>

      <h2 class="text-xl font-semibold mt-6">Getting Started</h2>
      <p>
        All courses listed above are available online at no cost and can be completed at your
        own pace. We encourage new members to complete IS-100, IS-200, IS-700, and IS-800 as a
        foundation for emergency communications work.
      </p>
      <p :if={@current_scope}>
        Approved members can record completed courses and certifications, with evidence
        uploads, from their <.link navigate={~p"/app/profile"} class="link link-primary">profile</.link>.
      </p>
      <p class="text-base-content/70">
        For questions about training requirements or to share your completed certifications
        with the organization, please contact <a
          class="link"
          href="mailto:secretary@monroecountyemcomm.org"
        >secretary@monroecountyemcomm.org</a>.
      </p>
    </Layouts.app>
    """
  end
end
