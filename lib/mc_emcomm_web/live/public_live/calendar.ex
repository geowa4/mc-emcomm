defmodule McEmcommWeb.PublicLive.Calendar do
  use McEmcommWeb, :live_view

  @calendar_id "c_47a34a906f34ba27c6cacde7a168a110957160035817b408d2553b62434fc3f7%40group.calendar.google.com"
  @calendar_embed_src "https://calendar.google.com/calendar/embed?src=#{@calendar_id}&ctz=America%2FNew_York"
  @calendar_ics_url "https://calendar.google.com/calendar/ical/#{@calendar_id}/public/basic.ics"
  @calendar_subscribe_url "https://calendar.google.com/calendar/u/0?cid=Y180N2EzNGE5MDZmMzRiYTI3YzZjYWNkZTdhMTY4YTExMDk1NzE2MDAzNTgxN2I0MDhkMjU1M2I2MjQzNGZjM2Y3QGdyb3VwLmNhbGVuZGFyLmdvb2dsZS5jb20"

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: "Calendar",
       meta_description:
         "Upcoming Monroe County ARES/RACES meetings, nets, training sessions, and public " <>
           "service events, with a calendar you can subscribe to.",
       calendar_embed_src: @calendar_embed_src,
       calendar_ics_url: @calendar_ics_url,
       calendar_subscribe_url: @calendar_subscribe_url
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} active_net={@active_net}>
      <.header>Calendar</.header>

      <p>
        Meetings, nets, and operations. We meet monthly except during July, August, and
        December.
      </p>

      <div class="flex flex-wrap gap-3 items-center">
        <a
          class="btn btn-primary btn-sm"
          href={@calendar_subscribe_url}
          target="_blank"
          rel="noopener"
        >
          Subscribe (Google Calendar)
        </a>
        <button
          id="copy-ics-btn"
          type="button"
          class="btn btn-outline btn-sm"
          phx-hook=".CopyIcs"
          data-ics-url={@calendar_ics_url}
        >
          Copy ICS link
        </button>
        <script :type={Phoenix.LiveView.ColocatedHook} name=".CopyIcs">
          export default {
            mounted() {
              this.el.addEventListener("click", () => {
                navigator.clipboard.writeText(this.el.dataset.icsUrl).then(() => {
                  const original = this.el.textContent
                  this.el.textContent = "Copied!"
                  setTimeout(() => { this.el.textContent = original }, 2000)
                })
              })
            }
          }
        </script>
      </div>

      <div class="mt-4 aspect-video w-full">
        <iframe
          src={@calendar_embed_src}
          class="w-full h-full border border-base-300 rounded-box"
          loading="lazy"
        ></iframe>
      </div>

      <p class="text-sm text-base-content/70">
        ICS feed: <a class="link break-all" href={@calendar_ics_url}>{@calendar_ics_url}</a>
      </p>

      <p class="mt-4 text-sm text-base-content/70">
        See also the <.link navigate={~p"/operations"} class="link">operation schedule</.link>.
      </p>
    </Layouts.app>
    """
  end
end
