import Auth from "./auth.js"

// Base hooks
let Hooks = {};

/**
 * Listen and request access trigger for the fullscreen click event
 */
Hooks.FullscreenIframe = {
  mounted() {
    document.getElementById("fullscreen-btn").addEventListener("click", () => {
      const iframe = document.querySelector("iframe");
      if (iframe && iframe.requestFullscreen) {
        iframe.requestFullscreen();
      }
    });
  },
};

/**
 * Copy to the clipboard
 */
Hooks.CopyToClipboard = {
  mounted() {
    this.handleEvent("copy_to_clipboard", ({ text }) => {
      navigator.clipboard
        .writeText(text)
        .then(() => {
          // Some logging or pushing event to the server to render UI
        })
        .catch((err) => {
          // Push errors here to the liveview
        });
    });
  },
};

Hooks.ChatScroll = {
  mounted() {
    this.el.scrollTop = this.el.scrollHeight;
  },
  updated() {
    this.el.scrollTop = this.el.scrollHeight;
  },
};

Hooks.Typewriter = {
  mounted() {
    this._done = false;
    this._maybeAnimate();
  },
  updated() {
    // Never re-animate once done
  },
  _maybeAnimate() {
    if (this._done) return;
    if (this.el.dataset.animate !== "true") return;

    this._done = true;

    // Grab the server-rendered HTML, clear the element, then type it back in
    const html = this.el.innerHTML;
    this.el.innerHTML = "";

    const temp = document.createElement("div");
    temp.innerHTML = html;

    const output = document.createElement("div");
    this.el.appendChild(output);

    const steps = [];

    const collectSteps = (parent, targetParent) => {
      for (const node of parent.childNodes) {
        if (node.nodeType === Node.TEXT_NODE) {
          if (node.textContent.length > 0) {
            const empty = document.createTextNode("");
            steps.push({ type: "text", text: node.textContent, node: empty, parent: targetParent });
          }
        } else if (node.nodeType === Node.ELEMENT_NODE) {
          const tag = node.tagName.toLowerCase();
          const isBlock = /^(p|h[1-6]|li|pre|blockquote|div|ul|ol|hr|table|tr)$/.test(tag);
          const clone = node.cloneNode(false);
          steps.push({ type: isBlock ? "block" : "inline", node: clone, parent: targetParent });
          collectSteps(node, clone);
        }
      }
    };

    collectSteps(temp, output);

    const scroller = this.el.closest(".system-scroll");
    const scrollDown = () => { if (scroller) scroller.scrollTop = scroller.scrollHeight; };

    let stepIdx = 0;
    let charIdx = 0;

    const tick = () => {
      if (stepIdx >= steps.length) {
        scrollDown();
        return;
      }

      const step = steps[stepIdx];

      if (step.type === "block" || step.type === "inline") {
        step.parent.appendChild(step.node);
        stepIdx++;
        scrollDown();
        setTimeout(tick, step.type === "block" ? 30 : 0);
        return;
      }

      if (charIdx === 0) step.parent.appendChild(step.node);

      const chunk = Math.min(2, step.text.length - charIdx);
      step.node.textContent = step.text.slice(0, charIdx + chunk);
      charIdx += chunk;

      if (charIdx >= step.text.length) {
        stepIdx++;
        charIdx = 0;
      }

      if (charIdx % 6 === 0) scrollDown();
      setTimeout(tick, 10);
    };

    tick();
  },
};

Hooks.ChatInput = {
  mounted() {
    this.el.addEventListener("keydown", (e) => {
      if (e.key === "Enter" && !e.shiftKey) {
        e.preventDefault();
        const value = this.el.value.trim();
        if (value) {
          this.el.closest("form").dispatchEvent(
            new Event("submit", { bubbles: true, cancelable: true })
          );
          this.el.value = "";
          this.el.style.height = "auto";
        }
      }
    });

    this.el.addEventListener("input", () => {
      this.el.style.height = "auto";
      this.el.style.height = Math.min(this.el.scrollHeight, 128) + "px";
    });
  },
};

export default {
  ...Hooks,
  Auth
};
