defmodule TunneldWeb.Live.Components.EnrollmentWizard do
  @moduledoc """
  Multi-step machine enrollment wizard (TODO §6 onboarding).

  Enrollment is multi-step and involves an out-of-band action (installing the
  public key), so the UI is a wizard with visible state:

    1. Name + address + SSH port + user + location → generate keypair
    2. Show the public key with a copy button and the exact `echo` command.
       This step blocks; the user must act outside Tunneld. Say so plainly.
    3. Test connection → success or a specific error (auth failed / unreachable /
       host key changed), never a generic failure.
    4. Probe → show discovered OS, arch, resources, runtimes; auto-install
       the WireGuard overlay for remote machines.

  Every step shows what will happen on the remote machine before it happens.
  Exit node capability is managed from the machine panel, not the wizard.
  """

  use TunneldWeb, :live_component

  alias Tunneld.Machines

  @impl true
  def mount(socket) do
    {:ok,
     assign(socket,
       step: 1,
       machine: nil,
       public_key: nil,
       error: nil,
       probing: false,
       overlay_status: nil,
       overlay_error: nil
     )}
  end

  @impl true
  def update(assigns, socket) do
    {:ok, assign(socket, open: Map.get(assigns, :open, false))}
  end

  @impl true
  def handle_event("wizard_enroll", params, socket) do
    case Machines.enroll(params) do
      {:ok, %{"id" => id, "public_key" => pub, "machine" => machine}} ->
        {:noreply,
         socket
         |> assign(step: 2, machine_id: id, machine: machine, public_key: pub, error: nil)}

      {:error, reason} ->
        {:noreply, assign(socket, error: reason)}
    end
  end

  def handle_event("wizard_test_connection", _params, socket) do
    id = socket.assigns.machine_id

    # Test connection by probing; report a specific error on failure. The probe
    # is synchronous, so assign the result directly (a live_component has no
    # process of its own; send(self(), ...) would go to the parent LiveView).
    result =
      case Machines.probe(id) do
        {:ok, machine} -> {:ok, machine}
        {:error, {:ssh_failed, _}} -> {:error, "SSH auth failed - is the public key installed?"}
        {:error, reason} -> {:error, "Connection failed: #{inspect(reason)}"}
      end

    case result do
      {:ok, machine} ->
        # Probe succeeded - transition to step 4 and start async overlay installation
        socket =
          socket
          |> assign(step: 4, machine: machine, probing: false, error: nil)
          |> assign(overlay_status: :installing)
          |> start_async(:install_overlay, fn -> install_overlay(machine) end)

        {:noreply, socket}

      {:error, reason} ->
        {:noreply, assign(socket, step: 3, probing: false, error: reason)}
    end
  end

  def handle_event("wizard_close", _params, socket) do
    # The parent owns the open state (it re-renders this component from
    # @enroll_wizard_open). Tell the parent to close so the modal stays
    # closed instead of being re-opened on the next parent re-render.
    send(socket.parent_pid, :wizard_closed)
    {:noreply, assign(socket, open: false)}
  end

  defp install_overlay(machine) do
    # Run ensure_peer which SSHes to target and installs wireguard-tools
    # This can take tens of seconds, hence the async execution
    Tunneld.Overlay.ensure_peer(machine)
  end

  def handle_info({:wizard_probe_result, result}, socket) do
    case result do
      {:ok, machine} ->
        {:noreply, assign(socket, step: 4, machine: machine, probing: false, error: nil)}

      {:error, reason} ->
        {:noreply, assign(socket, step: 3, probing: false, error: reason)}
    end
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  # Handle async overlay installation results
  @impl true
  def handle_async(:install_overlay, {:ok, :ok}, socket) do
    {:noreply, assign(socket, overlay_status: :success, overlay_error: nil)}
  end

  def handle_async(:install_overlay, {:ok, {:ok, _}}, socket) do
    {:noreply, assign(socket, overlay_status: :success, overlay_error: nil)}
  end

  def handle_async(:install_overlay, {:ok, {:error, reason}}, socket) do
    # Overlay install failed - enrollment still succeeds, but record the failure
    {:noreply, assign(socket, overlay_status: :failed, overlay_error: inspect(reason))}
  end

  def handle_async(:install_overlay, {:exit, reason}, socket) do
    # Task crashed - enrollment still succeeds, but record the failure
    {:noreply,
     assign(socket, overlay_status: :failed, overlay_error: "Task failed: #{inspect(reason)}")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id="enrollment-wizard-root">
      <div
        :if={@open}
        class="fixed inset-0 bg-black/70 flex items-center justify-center z-[100]"
        phx-window-keydown="wizard_close"
        phx-key="escape"
        phx-target={@myself}
      >
        <div
          class="bg-surface rounded-2xl p-6 max-w-[560px] w-full relative border border-border max-h-[90vh] overflow-y-auto system-scroll"
          phx-click-away="wizard_close"
          phx-target={@myself}
        >
          <div
            phx-click="wizard_close"
            phx-target={@myself}
            class="absolute top-0 right-0 p-3 cursor-pointer text-text-tertiary hover:text-text-primary"
          >
            <.icon name="hero-x-mark-solid" class="h-5 w-5" />
          </div>
          <h2 class="text-xl font-medium mb-1">Enroll Machine</h2>
          <div class="text-xs text-text-tertiary mb-4">Step <%= @step %> of 4</div>

          <%= render_step(assigns) %>
        </div>
      </div>
    </div>
    """
  end

  defp render_step(%{step: 1} = assigns) do
    ~H"""
    <div class="space-y-3">
      <p class="text-sm text-text-secondary">
        Enter the machine's details. Tunneld will generate an Ed25519 keypair and show you the
        public half to install on the target.
      </p>
      <form phx-submit="wizard_enroll" phx-target={@myself} class="space-y-3">
        <div class="grid grid-cols-2 gap-3">
          <input name="name" placeholder="Name" required class="tunl-input col-span-2" />
          <input name="address" placeholder="Address / IP" required class="tunl-input col-span-2" />
          <input name="ssh_port" placeholder="SSH port" value="22" class="tunl-input" />
          <input name="ssh_user" placeholder="SSH user" value="root" class="tunl-input" />
        </div>
        <div class="flex items-center gap-2">
          <span class="text-xs text-text-tertiary">Location:</span>
          <select name="location" class="tunl-input !w-auto">
            <option value="local">local</option>
            <option value="remote">remote</option>
          </select>
        </div>
        <button type="submit" class="w-full bg-accent p-2 rounded-md text-white text-sm">
          Generate keypair →
        </button>
      </form>
      <p :if={@error} class="text-xs text-red"><%= @error %></p>
    </div>
    """
  end

  defp render_step(%{step: 2} = assigns) do
    ~H"""
    <div class="space-y-3">
      <div class="bg-yellow/10 border border-yellow/30 rounded-lg p-3 text-xs text-warn">
        <b>This step blocks.</b> You must act outside Tunneld: install the public key on the target
        before continuing.
      </div>
      <p class="text-sm text-text-secondary">
        Install this public key on the target's <code>~/.ssh/authorized_keys</code>:
      </p>
      <pre class="bg-code border border-border rounded p-2 text-[10px] overflow-x-auto"><%= @public_key %></pre>
      <div class="flex items-center gap-2">
        <code class="text-[10px] bg-code border border-border rounded p-1 flex-1 overflow-x-auto">
          echo '<%= @public_key %>' &gt;&gt; ~/.ssh/authorized_keys
        </code>
        <button
          type="button"
          id="wizard_copy_key"
          phx-hook="CopyToClipboard"
          data-copy-text={"echo '#{@public_key}' >> ~/.ssh/authorized_keys"}
          class="ghost-btn !px-2 !py-1 text-[10px]"
        >
          copy
        </button>
      </div>
      <button
        phx-click="wizard_test_connection"
        phx-target={@myself}
        class="w-full bg-accent p-2 rounded-md text-white text-sm"
      >
        I've installed the key — test connection →
      </button>
    </div>
    """
  end

  defp render_step(%{step: 3} = assigns) do
    ~H"""
    <div class="space-y-3">
      <p class="text-sm text-text-secondary">Testing the SSH connection to the target...</p>
      <p :if={@probing} class="text-xs text-text-tertiary">Probing...</p>
      <p :if={@error} class="text-xs text-red"><%= @error %></p>
      <button
        :if={@error}
        phx-click="wizard_test_connection"
        phx-target={@myself}
        class="w-full bg-accent p-2 rounded-md text-white text-sm"
      >
        Retry
      </button>
    </div>
    """
  end

  defp render_step(%{step: 4} = assigns) do
    caps = Map.get(assigns.machine || %{}, "capabilities", %{})
    runtimes = Map.get(caps, "detected_runtimes", [])
    assigns = assign(assigns, caps: caps, runtimes: runtimes)

    ~H"""
    <div class="space-y-3">
      <p class="text-sm text-text-secondary">Connection succeeded. Discovered:</p>
      <div class="bg-surface rounded-lg p-3 text-xs space-y-1">
        <div><b>OS:</b> <%= @caps["os"] %></div>
        <div><b>Kernel:</b> <%= @caps["kernel"] %></div>
        <div><b>Arch:</b> <%= @caps["arch"] %></div>
        <div><b>CPU:</b> <%= @caps["cpu_count"] %> · <b>RAM:</b> <%= @caps["memory_mb"] %> MB</div>
        <div>
          <b>Runtimes:</b> <%= if @runtimes == [],
            do: "none detected",
            else: Enum.join(@runtimes, ", ") %>
        </div>
      </div>

      <%!-- WireGuard overlay installation status --%>
      <div class="bg-surface rounded-lg p-3 text-xs">
        <div class="flex items-center gap-2">
          <%= case @overlay_status do %>
            <% :installing -> %>
              <svg
                class="animate-spin h-4 w-4 text-accent"
                xmlns="http://www.w3.org/2000/svg"
                fill="none"
                viewBox="0 0 24 24"
              >
                <circle
                  class="opacity-25"
                  cx="12"
                  cy="12"
                  r="10"
                  stroke="currentColor"
                  stroke-width="4"
                >
                </circle>
                <path
                  class="opacity-75"
                  fill="currentColor"
                  d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"
                >
                </path>
              </svg>
              <span class="text-text-secondary">Installing WireGuard overlay...</span>
            <% :success -> %>
              <svg
                class="h-4 w-4 text-green-500"
                fill="none"
                viewBox="0 0 24 24"
                stroke="currentColor"
              >
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  stroke-width="2"
                  d="M5 13l4 4L19 7"
                >
                </path>
              </svg>
              <span class="text-green-500">WireGuard overlay installed</span>
            <% :failed -> %>
              <svg class="h-4 w-4 text-red-500" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  stroke-width="2"
                  d="M6 18L18 6M6 6l12 12"
                >
                </path>
              </svg>
              <span class="text-red-500">WireGuard installation failed</span>
            <% _ -> %>
              <span class="text-text-tertiary">Preparing overlay...</span>
          <% end %>
        </div>
        <p :if={@overlay_error} class="mt-2 text-red-400 text-[10px]"><%= @overlay_error %></p>
        <p :if={@overlay_status == :failed} class="mt-1 text-text-tertiary text-[10px]">
          Machine enrolled successfully. You can install the overlay later from the machine panel.
        </p>
      </div>

      <div class="flex flex-col gap-2 pt-2">
        <button
          phx-click="wizard_close"
          phx-target={@myself}
          class="w-full bg-accent p-2 rounded-md text-white text-sm"
        >
          Done
        </button>
      </div>
    </div>
    """
  end

  defp render_step(_), do: nil
end
