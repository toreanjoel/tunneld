# Acceptance criteria: polish

- compile --warnings-as-errors, mix test, mix format pass
- .xterm-viewport has themed scrollbars for both webkit and firefox, reusing the app's #25232f thumb
- An accelerated renderer (webgl, with canvas/DOM fallback) is vendored and used, so the terminal is not on the slow DOM renderer
- The renderer has a fallback path if WebGL is unavailable never a blank terminal
- Terminal resize is debounced; scrollback is bounded sensibly
- No runtime CDN reference for terminal assets the gateway is LAN-only
- The curriculum gate passes, including a new 18-terminal-exec.html page
- The terminal page documents the three bugs found in production: phx-update=ignore, _csrf_token for connect_info, and user_dir key auth
- mix assets.build succeeds and every ../vendor/ file the terminal hook imports exists on disk
