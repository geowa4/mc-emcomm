defmodule McEmcommWeb.PublicLive.Calendar do
  use McEmcommWeb, :live_view

  @calendar_embed_src "https://calendar.google.com/calendar/embed?src=8_89aa1e27a5a540b2c4f4988aa6d9a1480e65fa873f341eccf3bda2b461f6df7%40group.calendar.google.com&ctz=America%2FNew_York"

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: "Calendar", calendar_embed_src: @calendar_embed_src)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>Calendar</.header>

      <p>
        Meetings, nets, and exercises. We meet monthly except during July, August, and
        December.
      </p>

      <div class="mt-4 aspect-video w-full">
        <iframe
          src={@calendar_embed_src}
          class="w-full h-full border border-base-300 rounded-box"
          loading="lazy"
        ></iframe>
      </div>

      <p class="mt-4 text-sm text-base-content/70">
        See also the <.link navigate={~p"/exercises"} class="link">exercise schedule</.link>.
      </p>
    </Layouts.app>
    """
  end
end
