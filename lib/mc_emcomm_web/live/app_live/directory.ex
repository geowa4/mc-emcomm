defmodule McEmcommWeb.AppLive.Directory do
  @moduledoc """
  The member directory (§30): approved members on a map and in a searchable,
  sorted, paged list. The search, order, and page live in the URL, so a view
  of the directory can be linked to and survives a reload.
  """

  use McEmcommWeb, :live_view

  alias McEmcomm.Members
  alias McEmcommWeb.MapHelpers
  alias McEmcommWeb.ParamHelpers

  @default_order "name"

  @orders %{
    "name" => {:name, :asc},
    "name-desc" => {:name, :desc},
    "call-sign" => {:call_sign, :asc},
    "call-sign-desc" => {:call_sign, :desc}
  }

  @order_options [
    {"Name (A to Z)", "name"},
    {"Name (Z to A)", "name-desc"},
    {"Call sign (A to Z)", "call-sign"},
    {"Call sign (Z to A)", "call-sign-desc"}
  ]

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(
       page_title: "Member Directory",
       tile_url: MapHelpers.tile_url(),
       order_options: @order_options
     )
     |> stream_configure(:members, dom_id: &"directory-member-#{&1.id}")}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    search = search_param(params["q"])
    order = order_param(params["order"])
    {sort, direction} = Map.fetch!(@orders, order)

    directory =
      Members.list_directory(
        search: search,
        sort: sort,
        direction: direction,
        page: ParamHelpers.id(params["page"])
      )

    located = Members.list_directory_locations(search: search)

    {:noreply,
     socket
     |> assign(
       search: search,
       order: order,
       form: to_form(%{"q" => search, "order" => order}),
       page: directory.page,
       per_page: directory.per_page,
       total_count: directory.total_count,
       total_pages: directory.total_pages,
       shown_count: length(directory.entries),
       located_count: length(located),
       markers_json: markers_json(located)
     )
     |> stream(:members, directory.entries, reset: true)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} active_net={@active_net}>
      <.header>
        Member Directory
        <:subtitle>Approved members. Visible to members only.</:subtitle>
      </.header>

      <.form
        for={@form}
        id="directory-search-form"
        phx-change="search"
        phx-submit="search"
        class="flex flex-wrap gap-x-4 items-end"
      >
        <.input
          field={@form[:q]}
          id="directory-search"
          type="search"
          label="Search by name, call sign, or email"
          autocomplete="off"
          maxlength="100"
          phx-debounce="300"
        />
        <.input
          field={@form[:order]}
          id="directory-order"
          type="select"
          label="Sort by"
          options={@order_options}
        />
      </.form>

      <section aria-labelledby="directory-map-heading" class="mt-4">
        <h2 id="directory-map-heading" class="text-lg font-semibold">Map</h2>
        <p id="directory-map-summary" class="text-sm text-base-content/70 mb-1">
          {map_summary(@located_count, @total_count, @search)} The list below gives the same locations as coordinates.
        </p>
        <.static_map
          id="directory-map"
          label="Map of member home locations"
          markers_json={@markers_json}
          tile_url={@tile_url}
        />
      </section>

      <section aria-labelledby="directory-list-heading" class="mt-8">
        <h2 id="directory-list-heading" class="text-lg font-semibold">Members</h2>
        <p id="directory-count" role="status" class="text-sm text-base-content/70">
          {count_summary(@page, @per_page, @shown_count, @total_count)}
        </p>
        <p :if={@total_count == 0} id="directory-empty" class="mt-2">
          No members match “{@search}”.
          <.link id="directory-clear-search" patch={~p"/app/directory"} class="link">
            Clear the search
          </.link>
        </p>

        <.table :if={@total_count > 0} id="directory-members" rows={@streams.members}>
          <:col :let={{_id, m}} label="Name">{m.name}</:col>
          <:col :let={{_id, m}} label="Call sign">
            <span class="font-mono">{m.call_sign}</span>
          </:col>
          <:col :let={{_id, m}} label="Email">
            <a href={"mailto:#{m.user.email}"} class="link link-hover">{m.user.email}</a>
          </:col>
          <:col :let={{_id, m}} label="License class">
            {m.license_class && Phoenix.Naming.humanize(m.license_class)}
          </:col>
          <:col :let={{_id, m}} label="Positions">
            {Enum.map_join(m.positions, ", ", & &1.name)}
          </:col>
          <:col :let={{_id, m}} label="Home location">
            <span :if={m.qth_point} class="font-mono text-sm">{coordinates(m.qth_point)}</span>
            <span :if={!m.qth_point} class="text-base-content/70">Not set</span>
          </:col>
        </.table>

        <nav
          :if={@total_pages > 1}
          id="directory-pagination"
          aria-label="Member list pages"
          class="mt-4 flex items-center justify-between gap-4"
        >
          <.link
            :if={@page > 1}
            id="directory-previous-page"
            patch={directory_path(@search, @order, @page - 1)}
            class="btn btn-sm"
            rel="prev"
          >
            Previous <span class="sr-only">page</span>
          </.link>
          <span :if={@page == 1} class="btn btn-sm btn-disabled" aria-hidden="true">Previous</span>

          <span id="directory-page" aria-current="page" class="text-sm">
            Page {@page} of {@total_pages}
          </span>

          <.link
            :if={@page < @total_pages}
            id="directory-next-page"
            patch={directory_path(@search, @order, @page + 1)}
            class="btn btn-sm"
            rel="next"
          >
            Next <span class="sr-only">page</span>
          </.link>
          <span :if={@page == @total_pages} class="btn btn-sm btn-disabled" aria-hidden="true">
            Next
          </span>
        </nav>
      </section>
    </Layouts.app>
    """
  end

  # A new search or order starts again from the first page.
  @impl true
  def handle_event("search", params, socket) do
    path = directory_path(search_param(params["q"]), order_param(params["order"]), 1)
    {:noreply, push_patch(socket, to: path)}
  end

  defp search_param(search) when is_binary(search), do: String.trim(search)
  defp search_param(_search), do: ""

  defp order_param(order) when is_map_key(@orders, order), do: order
  defp order_param(_order), do: @default_order

  # Defaults are left out so the plain directory keeps a plain URL.
  defp directory_path(search, order, page) do
    params =
      [q: search, order: order, page: page]
      |> Enum.reject(fn pair -> pair in [q: "", order: @default_order, page: 1] end)

    ~p"/app/directory?#{params}"
  end

  defp markers_json(members) do
    members
    |> Enum.map(&%{point: &1.qth_point, title: marker_title(&1)})
    |> MapHelpers.markers_json()
  end

  defp marker_title(%{call_sign: nil, name: name}), do: name
  defp marker_title(%{call_sign: call_sign, name: name}), do: "#{call_sign} — #{name}"

  defp coordinates(point) do
    "#{coordinate(MapHelpers.lat(point))}, #{coordinate(MapHelpers.lng(point))}"
  end

  defp coordinate(value), do: :erlang.float_to_binary(value * 1.0, decimals: 4)

  defp map_summary(located, total, ""),
    do: "#{located} of #{total} #{members(total)} have set a home location."

  defp map_summary(located, total, _search),
    do: "#{located} of #{total} matching #{members(total)} have set a home location."

  defp count_summary(_page, _per_page, _shown, 0), do: "No members to show."

  defp count_summary(page, per_page, shown, total) do
    first = (page - 1) * per_page + 1
    "Showing #{first} to #{first + shown - 1} of #{total} #{members(total)}."
  end

  defp members(1), do: "member"
  defp members(_count), do: "members"
end
