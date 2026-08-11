# Acceptance criteria: fleet

- compile --warnings-as-errors, mix test, mix format, mix assets.build all pass
- Terminal status/error lookup is not scoped to this.el (the status element is a sibling, not a child)
- SSH/connection failures are written into the terminal surface so the user sees WHY it is empty
- Enrolling a machine installs the WireGuard overlay automatically (Overlay.ensure_peer)
- No separate 'Install WireGuard' or 'Make Exit Node' step in the wizard the overlay is implied
- Machine removal bounds remote teardown with a timeout and always deletes local state, so a dead host cannot block deletion
- No regression of: _csrf_token, phx-update=ignore, user_dir auth, xterm scrollbar theme
- The wizard_install_wg / wizard_make_exit handlers are gone AND ensure_peer is still invoked from the automatic enrollment path (not merely present in the file)
