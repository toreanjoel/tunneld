/**
 * Terminal hook for interactive SSH sessions via Phoenix channels.
 *
 * This hook:
 * - Boots xterm.js with proper theming
 * - Joins the exec channel for the machine
 * - Pipes data bidirectionally (browser <-> gateway <-> target)
 * - Sends resize events when the terminal dimensions change
 * - Cleans up properly on disconnect
 *
 * Performance: Uses WebGL renderer with canvas/DOM fallback, debounced resize.
 *
 * Security: This module handles terminal I/O only. All authentication is
 * performed server-side by the gateway - no secrets reach the browser.
 */

// The vendored xterm builds are UMD:
//   if (typeof exports === "object" && typeof module === "object") module.exports = t()
// esbuild bundles them as CommonJS, so that first branch wins and the globals
// branch (e.global.Terminal = ...) never runs. A bare `import "..."` therefore
// leaves window.Terminal undefined. Bind the module exports directly instead.
// NB: both builds set __esModule:true but export NO `default`, so a default
// import yields undefined. A namespace import is required to reach .Terminal.
import * as XtermMod from "../vendor/xterm.js";
import * as FitMod from "../vendor/xterm-addon-fit.js";

// Theme matching the Tunneld dashboard
const THEME = {
  background: '#0B0A14',
  foreground: '#E5E5E5',
  cursor: '#06B6D4',
  cursorAccent: '#0B0A14',
  selectionBackground: '#06B6D4',
  selectionForeground: '#0B0A14',
  black: '#0B0A14',
  red: '#EF4444',
  green: '#22C55E',
  yellow: '#F59E0B',
  blue: '#3B82F6',
  magenta: '#A855F7',
  cyan: '#06B6D4',
  white: '#E5E5E5',
  brightBlack: '#4B5563',
  brightRed: '#F87171',
  brightGreen: '#4ADE80',
  brightYellow: '#FBBF24',
  brightBlue: '#60A5FA',
  brightMagenta: '#C084FC',
  brightCyan: '#22D3EE',
  brightWhite: '#FFFFFF',
};

const TerminalHook = {
  mounted() {
    const machineId = this.el.dataset.machineId;
    if (!machineId) {
      console.error("Terminal: No machine ID provided");
      this.setStatus("error", "No machine ID");
      return;
    }

    this.machineId = machineId;
    this.channel = null;
    this.term = null;
    this.fitAddon = null;
    this.rendererAddon = null;
    this.resizeObserver = null;
    this.resizeTimeout = null;

    this.initTerminal();
    this.connectChannel();
  },

  destroyed() {
    this.cleanup();
  },

  initTerminal() {
    const container = this.el.querySelector('.terminal-container');
    if (!container) {
      console.error("Terminal: No container element found");
      return;
    }

    // Prefer the bundled module exports; fall back to globals if a future build
    // is loaded via a plain <script> tag.
    const Terminal =
      XtermMod?.Terminal || XtermMod?.default?.Terminal || window.Terminal;
    const FitAddon =
      FitMod?.FitAddon || FitMod?.default?.FitAddon || window.FitAddon?.FitAddon;

    if (!Terminal) {
      console.error("Terminal: xterm.js not loaded");
      this.setStatus("error", "Terminal library not loaded");
      return;
    }

    // Create terminal instance with bounded scrollback for responsiveness
    this.term = new Terminal({
      theme: THEME,
      fontFamily: '"JetBrains Mono", "Fira Code", "Monaco", monospace',
      fontSize: 14,
      lineHeight: 1.2,
      cursorBlink: true,
      cursorStyle: 'block',
      scrollback: 5000,
      allowProposedApi: true,
    });

    // Fit addon for auto-sizing
    if (FitAddon) {
      this.fitAddon = new FitAddon();
      this.term.loadAddon(this.fitAddon);
    }

    // Open the terminal in the container
    this.term.open(container);

    // NOTE: no GPU renderer addon. WebGL/canvas were tried and reverted - see
    // the comment on loadAcceleratedRenderer's removal in git history. xterm's
    // default DOM renderer is slower but renders reliably at any container size.

    // Initial fit
    setTimeout(() => {
      if (this.fitAddon) {
        this.fitAddon.fit();
      }
    }, 0);

    // Handle input from the terminal
    this.term.onData((data) => {
      if (this.channel) {
        this.channel.push("data", { data });
      }
    });

    // Debounced resize observer to avoid flooding fit()+sendResize() on every frame
    this.resizeObserver = new ResizeObserver(() => {
      if (this.resizeTimeout) {
        clearTimeout(this.resizeTimeout);
      }
      this.resizeTimeout = setTimeout(() => {
        if (this.fitAddon && this.term) {
          this.fitAddon.fit();
          this.sendResize();
        }
      }, 50);
    });
    this.resizeObserver.observe(container);
  },

  connectChannel() {
    this.setStatus("connecting", "Connecting...");

    // Phoenix only populates connect_info[:session] when a VALID _csrf_token
    // param is present (phoenix/lib/phoenix/socket/transport.ex:492). Without it
    // the session is nil server-side and every connect is refused with 403.
    // This is the same thing LiveView's own socket does. The CSRF token is not a
    // credential - auth still comes from the signed HttpOnly session cookie.
    const csrfToken = document
      .querySelector("meta[name='csrf-token']")
      ?.getAttribute("content");

    const socket = new window.Phoenix.Socket("/ws", {
      params: { _csrf_token: csrfToken },
    });

    socket.connect();

    socket.onError(() => {
      this.setStatus("error", "Socket connection failed");
    });

    // Join the exec channel for this machine
    const cols = this.term ? this.term.cols : 80;
    const rows = this.term ? this.term.rows : 24;

    this.channel = socket.channel(`exec:${this.machineId}`, { cols, rows });

    this.channel.on("connected", () => {
      this.setStatus("connected", "Connected");
      if (this.term) {
        this.term.focus();
      }
    });

    this.channel.on("data", ({ data }) => {
      if (this.term && data) {
        // Data is base64 encoded
        try {
          const decoded = atob(data);
          this.term.write(decoded);
        } catch (e) {
          console.error("Terminal: Failed to decode data", e);
        }
      }
    });

    this.channel.on("closed", ({ reason }) => {
      const msg = reason || "Connection closed";
      this.setStatus("disconnected", msg);
      // Write to terminal so the user sees why the session ended
      if (this.term) {
        this.term.writeln('\x1b[33m');  // Yellow for closed/disconnected
        this.term.writeln(`\r\n[Session closed: ${msg}]`);
        this.term.writeln('\x1b[0m');
      }
    });

    this.channel.on("error", ({ reason }) => {
      const msg = reason || "Connection error";
      this.setStatus("error", msg);
      this.writeTerminalError(msg);
    });

    this.channel.join()
      .receive("ok", () => {
        // Wait for the "connected" event from SSH
      })
      .receive("error", ({ reason }) => {
        const msg = reason || "Failed to join channel";
        this.setStatus("error", msg);
        this.writeTerminalError(msg);
      })
      .receive("timeout", () => {
        const msg = "Connection timeout";
        this.setStatus("error", msg);
        this.writeTerminalError(msg);
      });

    this.socket = socket;
  },

  sendResize() {
    if (this.channel && this.term) {
      this.channel.push("resize", {
        cols: this.term.cols,
        rows: this.term.rows
      });
    }
  },

  setStatus(state, message) {
    // Status elements are in the modal header, a SIBLING of the hook element,
    // not a descendant. Find them via document.getElementById / querySelector.
    const statusEl = document.getElementById('terminal-status');
    const statusTextEl = statusEl?.querySelector('.terminal-status-text');
    const statusIconEl = statusEl?.querySelector('.terminal-status-icon');

    if (statusTextEl) {
      statusTextEl.textContent = message;
    }

    if (statusEl) {
      statusEl.dataset.state = state;
    }

    if (statusIconEl) {
      switch (state) {
        case "connecting":
          statusIconEl.innerHTML = `<svg class="animate-spin h-4 w-4" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24"><circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle><path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path></svg>`;
          break;
        case "connected":
          statusIconEl.innerHTML = `<svg class="h-4 w-4 text-green-500" fill="none" viewBox="0 0 24 24" stroke="currentColor"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7"></path></svg>`;
          break;
        case "error":
        case "disconnected":
          statusIconEl.innerHTML = `<svg class="h-4 w-4 text-red-500" fill="none" viewBox="0 0 24 24" stroke="currentColor"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12"></path></svg>`;
          break;
      }
    }
  },

  // Write error messages into the terminal surface so users see WHY it's empty
  writeTerminalError(message) {
    if (this.term) {
      // Use ANSI red color for error messages
      this.term.writeln('\x1b[31m');
      this.term.writeln('═'.repeat(60));
      this.term.writeln('  Connection Error');
      this.term.writeln('═'.repeat(60));
      this.term.writeln('');
      this.term.writeln(`  ${message}`);
      this.term.writeln('');
      this.term.writeln('  Check the machine panel for troubleshooting options.');
      this.term.writeln('═'.repeat(60));
      this.term.writeln('\x1b[0m');
    }
  },

  cleanup() {
    if (this.resizeTimeout) {
      clearTimeout(this.resizeTimeout);
      this.resizeTimeout = null;
    }

    if (this.resizeObserver) {
      this.resizeObserver.disconnect();
      this.resizeObserver = null;
    }

    if (this.channel) {
      this.channel.leave();
      this.channel = null;
    }

    if (this.socket) {
      this.socket.disconnect();
      this.socket = null;
    }

    if (this.rendererAddon) {
      this.rendererAddon.dispose();
      this.rendererAddon = null;
    }

    if (this.term) {
      this.term.dispose();
      this.term = null;
    }
  }
};

export default TerminalHook;
