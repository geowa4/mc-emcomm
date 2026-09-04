defmodule McEmcommWeb.PublicLive.About do
  use McEmcommWeb, :live_view

  alias McEmcomm.Members

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: "About",
       meta_description:
         "Who Monroe County ARES/RACES is, the leadership team, when we meet, the services " <>
           "we provide, how to become a member, and how to reach us.",
       positions: Members.list_positions()
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} active_net={@active_net}>
      <.header>About Monroe County ARES/RACES</.header>

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
      <ul id="leadership-list" class="list bg-base-100 rounded-box border border-base-300">
        <li :for={position <- @positions} id={"position-#{position.id}"} class="list-row">
          <div>
            <div class="font-semibold">{position.name}</div>
            <div :if={position.members == []} class="text-sm text-base-content/70 italic">
              Vacant
            </div>
            <div
              :for={member <- position.members}
              class="text-sm text-base-content/70"
            >
              {member.name}
              <span :if={member.call_sign}>· {member.call_sign}</span>
            </div>
          </div>
        </li>
      </ul>

      <h2 class="text-xl font-semibold mt-6">Meetings</h2>
      <p>
        We meet on the fourth Thursday of each month except during July, August, and
        December. These meetings provide opportunities for training and skill development,
        planning and coordination, equipment testing and maintenance, and fellowship and
        networking.
      </p>

      <section id="weekly-net" aria-labelledby="weekly-net-heading">
        <h2 id="weekly-net-heading" class="text-xl font-semibold mt-6">
          Weekly Net &amp; Repeaters
        </h2>
        <p>
          Our weekly net is held every Thursday at 7:00 PM local time on the primary repeater.
          All licensed amateurs are welcome to check in.
        </p>
        <dl id="repeaters" class="mt-2 grid gap-x-6 gap-y-1 sm:grid-cols-[auto_1fr]">
          <dt class="font-semibold">2 m primary — W2ARM</dt>
          <dd>146.610 MHz, -0.6 MHz offset (146.010 input), PL 110.9 Hz, Cobbs Hill, FM and P-25</dd>
          <dt class="font-semibold">70 cm — W2ARM</dt>
          <dd>444.450 MHz, +5 MHz offset, PL 110.9 Hz</dd>
        </dl>
        <p class="text-sm text-base-content/70 mt-2">
          The primary repeater's callsign changed from N2MPE to W2ARM; older listings may still
          show N2MPE.
        </p>
      </section>

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
        to apply — new accounts are reviewed by an EmComm admin before approval — or email <a
          class="link"
          href="mailto:secretary@monroecountyemcomm.org"
        >secretary@monroecountyemcomm.org</a>.
      </p>

      <h2 class="text-xl font-semibold mt-6">Contact</h2>
      <address class="not-italic space-y-1">
        <p>
          Monroe County Amateur Radio Emergency Services, Inc. · 1100 Jefferson Rd., Suite 12
          #1148 · Rochester, NY 14623
        </p>
        <p>
          General inquiries:
          <a class="link" href="mailto:secretary@monroecountyemcomm.org">secretary@monroecountyemcomm.org</a>
        </p>
        <p>
          Website issues:
          <a class="link" href="mailto:webmaster@monroecountyemcomm.org">webmaster@monroecountyemcomm.org</a>
        </p>
      </address>

      <h2 class="text-xl font-semibold mt-6">Social Media &amp; Community</h2>
      <ul id="social-links" class="list-disc list-inside space-y-1">
        <li>
          Facebook:
          <a class="link" href="https://www.facebook.com/MCARESNY" target="_blank" rel="noopener">
            Monroe County ARES <.new_tab_note />
          </a>
        </li>
        <li>
          X:
          <a class="link" href="https://x.com/MCARESNY" target="_blank" rel="noopener">
            @MCARESNY <.new_tab_note />
          </a>
        </li>
        <li>
          Groups.io:
          <a class="link" href="https://groups.io/g/MonroeCountyEmcomm" target="_blank" rel="noopener">
            Monroe County Emcomm <.new_tab_note />
          </a>
        </li>
        <li>
          Google Calendar:
          <a
            class="link"
            href="https://calendar.google.com/calendar/u/0?cid=Y180N2EzNGE5MDZmMzRiYTI3YzZjYWNkZTdhMTY4YTExMDk1NzE2MDAzNTgxN2I0MDhkMjU1M2I2MjQzNGZjM2Y3QGdyb3VwLmNhbGVuZGFyLmdvb2dsZS5jb20"
            target="_blank"
            rel="noopener"
          >
            Subscribe to our calendar <.new_tab_note />
          </a>
        </li>
      </ul>

      <h2 class="text-xl font-semibold mt-6">Emergency Communications</h2>
      <p>
        For actual emergency communications needs, please contact your local emergency
        management agency. Monroe County ARES/RACES operates under the direction of served
        agencies during emergency situations.
      </p>
    </Layouts.app>
    """
  end
end
