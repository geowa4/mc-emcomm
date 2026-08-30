defmodule McEmcommWeb.PublicLive.About do
  use McEmcommWeb, :live_view

  alias McEmcomm.Members

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: "About", leadership: Members.list_leadership())}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>About Monroe County EmComm</.header>

      <p>
        Monroe County ARES (Amateur Radio Emergency Service) is an organized group of licensed
        Amateur Radio operators who have volunteered their services to provide emergency
        communications support during disasters and other emergency situations.
      </p>

      <h2 class="text-xl font-semibold mt-6">Our Mission</h2>
      <p>
        We are dedicated to providing reliable backup communication services when normal
        communication systems fail or become overloaded. Our volunteers stand ready to assist
        emergency management agencies, served organizations, and the general public during
        times of need.
      </p>

      <h2 class="text-xl font-semibold mt-6">Leadership</h2>
      <ul :if={@leadership != []} class="list bg-base-100 rounded-box border border-base-300">
        <li :for={member <- @leadership} class="list-row">
          <div>
            <div class="font-semibold">{format_role(member.role)}</div>
            <div class="text-sm text-base-content/70">
              {member.name}
              <span :if={member.call_sign}>· {member.call_sign}</span>
            </div>
          </div>
        </li>
      </ul>
      <p :if={@leadership == []} class="text-base-content/70">Leadership roster coming soon.</p>

      <h2 class="text-xl font-semibold mt-6">Meetings</h2>
      <p>
        We hold monthly meetings except during July, August, and December. These meetings
        provide opportunities for training and skill development, planning and coordination,
        equipment testing and maintenance, and fellowship and networking.
      </p>

      <h2 class="text-xl font-semibold mt-6">Weekly Net &amp; Repeater</h2>
      <p class="text-base-content/70">
        Repeater frequency, offset, tone, and the weekly net schedule are pending final
        confirmation from leadership (a recent callsign transition on the primary repeater is
        still being verified) and will be published here once confirmed.
      </p>

      <h2 class="text-xl font-semibold mt-6">Services We Provide</h2>
      <ul class="list-disc list-inside space-y-1">
        <li>Emergency communications backup during disasters and emergencies</li>
        <li>Public service event support for community events, races, and gatherings</li>
        <li>Regular training programs for members and interested operators</li>
        <li>Community education about amateur radio and emergency preparedness</li>
      </ul>

      <h2 class="text-xl font-semibold mt-6">Membership</h2>
      <p>
        Membership is open to all licensed Amateur Radio operators committed to public service,
        from newly licensed technicians to seasoned extra class operators.
        <.link navigate={~p"/users/register"} class="link link-primary">Register</.link>
        to apply — new accounts are reviewed by an EmComm admin before approval.
      </p>

      <h2 class="text-xl font-semibold mt-6">Contact</h2>
      <address class="not-italic space-y-1">
        <p>Monroe County ARES/RACES · #1148 1100 Jefferson Road, Suite 12 · Rochester, NY 14623</p>
        <p>
          General inquiries:
          <a class="link" href="mailto:secretary@monroecountyemcomm.org">secretary@monroecountyemcomm.org</a>
        </p>
        <p>
          Website issues:
          <a class="link" href="mailto:webmaster@monroecountyemcomm.org">webmaster@monroecountyemcomm.org</a>
        </p>
      </address>
    </Layouts.app>
    """
  end

  defp format_role(role) do
    role
    |> to_string()
    |> String.replace("_", " ")
    |> String.split(" ")
    |> Enum.map_join(" ", &String.capitalize/1)
  end
end
