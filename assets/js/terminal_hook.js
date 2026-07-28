/**
 * TerminalHook — bridges a Phoenix channel exec session to a <pre> element.
 *
 * The hook expects a `data-topic` attribute on the mounted element in the
 * form `exec:<machine_id>:<container_name>`. On mount it opens a Phoenix
 * socket/channel, sends "start", and streams output into the <pre>.
 * Keystrokes on a hidden input are forwarded as "input" events.
 *
 * v1 is deliberately simple: a <pre> + hidden <input>, not xterm.js. ANSI
 * escape sequences are passed through raw (the browser renders them as
 * literal text). A later milestone can swap in xterm.js for proper rendering.
 */
const TerminalHook = {
  mounted() {
    const topic = this.el.dataset.topic;
    const pre = this.el.querySelector("pre");
    const input = this.el.querySelector("input.terminal-input");

    if (!topic || !pre || !input) return;

    const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content");
    const clientId = this.el.dataset.clientId || ""

    // Open a dedicated socket (separate from the LiveView socket)
    const socket = new Phoenix.Socket("/ws", {
      params: { client_id: clientId, _csrf_token: csrfToken }
    });
    socket.connect();

    const channel = socket.channel(topic, {});
    channel.join()
      .receive("ok", () => {
        channel.push("start", {});
        pre.textContent = "";
      })
      .receive("error", (resp) => {
        pre.textContent = "Failed to connect: " + JSON.stringify(resp);
      });

    channel.on("output", (msg) => {
      pre.textContent += msg.data;
      // Auto-scroll to bottom
      pre.scrollTop = pre.scrollHeight;
    });

    channel.on("exit", (msg) => {
      pre.textContent += "\n[process exited with code " + msg.code + "]";
    });

    // Forward keystrokes to the channel
    input.addEventListener("keydown", (e) => {
      // Enter sends a carriage return to the PTY
      if (e.key === "Enter") {
        channel.push("input", { data: input.value + "\r" });
        input.value = "";
        e.preventDefault();
      } else if (e.key === "Backspace") {
        channel.push("input", { data: "\b" });
        e.preventDefault();
      } else if (e.key === "Tab") {
        channel.push("input", { data: "\t" });
        e.preventDefault();
      } else if (e.key.length === 1 && !e.ctrlKey && !e.metaKey) {
        channel.push("input", { data: e.key });
        e.preventDefault();
      }
    });

    // Focus the input when the terminal area is clicked
    this.el.addEventListener("click", () => input.focus());

    this.socket = socket;
    this.channel = channel;
  },

  destroyed() {
    if (this.channel) this.channel.leave();
    if (this.socket) this.socket.disconnect();
  }
};

export default TerminalHook;