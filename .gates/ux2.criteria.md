# Acceptance criteria: ux2

- compile --warnings-as-errors, mix test, mix format all pass
- Toast: title and message stack vertically (not two wrapping flex columns), top-aligned, min-w-0, with clean word wrapping
- Device grid uses items-start so a tagged card does not resize every card in its row
- The border-t divider inside the device card is removed
- Tunneld.Servers.Devices exposes an immediate sync/refresh and a way to read current state
- Tag and lease mutations trigger an immediate resync instead of waiting for the 10s poll
- The devices list paints from current state on mount instead of a blind loading wait
- The modal BACKDROP element itself is click-dismissable (or the panel uses phx-click-away), and has an Escape handler - not merely an X button somewhere in the file
