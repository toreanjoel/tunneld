# Acceptance criteria: ui

- compile --warnings-as-errors, mix test, and mix format --check-formatted all pass
- Sidebar fetches listeners asynchronously (start_async/assign_async) and shows a loading state
- runtime.ex classifies/filters infrastructure listeners (sshd, caddy, dnsmasq, systemd-resolve)
- Redundant 'Exit' description text removed from the machine sidebar
- Machines list shows ONE status indicator, not two independently-green dots
- An SSH/terminal affordance exists in the machine sidebar
- Modal and wizard scroll with the themed system-scroll bar; invalid scrollbar-width CSS fixed
- Egress help icon renders once per section, not once per device card
- No border-b under the devices list header (padding preserved)
- Flash toasts have a bounded max-width and no raw inspect() output
- Map pins wired to MapPinHover with data-pin-* metadata so hover shows machine info
- Uppercase kind chip (HOST) removed from the machines list; location tags remain
- No JS hook registered in hooks.js is left unused in markup
- 
