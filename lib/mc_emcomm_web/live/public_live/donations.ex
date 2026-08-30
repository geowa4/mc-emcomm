defmodule McEmcommWeb.PublicLive.Donations do
  use McEmcommWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: "Donations")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>Support Monroe County EmComm</.header>

      <p>
        Your donations help Monroe County ARES/RACES maintain our capability to provide
        critical emergency communications services to our community. Even a small contribution
        helps offset our operational expenses.
      </p>

      <h2 class="text-xl font-semibold mt-6">How Your Donations Help</h2>
      <ul class="list-disc list-inside space-y-1">
        <li>Liability insurance protecting our volunteers while they serve the community</li>
        <li>Post office box fees for our official mailing address</li>
        <li>Web page and hosting expenses</li>
      </ul>

      <p class="mt-4">
        We suggest a donation of <strong>$10</strong>, though any amount is greatly appreciated.
      </p>

      <h2 class="text-xl font-semibold mt-6">How to Donate</h2>
      <p>
        <a
          class="btn btn-primary"
          href="https://www.zeffy.com/en-US/donation-form/donate-to-support-monroe-county-ares"
          target="_blank"
          rel="noopener"
        >
          Donate online via Zeffy
        </a>
      </p>

      <p class="mt-4">
        Or mail a check made payable to <strong>Monroe County Emergency Services</strong> to:
      </p>
      <address class="not-italic">
        Monroe County Emergency Services<br /> 1100 Jefferson Road, Suite 12 &ndash; #1148<br />
        Rochester, NY 14623
      </address>

      <p class="mt-6 text-base-content/70">
        Questions? Contact <a class="link" href="mailto:secretary@monroecountyemcomm.org">secretary@monroecountyemcomm.org</a>.
      </p>
    </Layouts.app>
    """
  end
end
