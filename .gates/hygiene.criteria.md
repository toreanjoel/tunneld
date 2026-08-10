# Acceptance criteria: hygiene

- mix compile --warnings-as-errors exits 0 with zero warnings
- mix test exits 0. Do NOT delete tests to pass; tautological tests may be replaced by real ones
- mix format --check-formatted exits 0 across lib/, test/, config/
- Dead modules deleted: geo_data/centroids.ex, schema/machine.ex, live/components/devices_summary.ex
- Dead functions removed: world_map/1, all_tags/0, ensure_lan_domain/0, find_service/1, get_service_logs/1
- Unreachable :incus_not_installed 424 branch removed
- No stale 'incus' refs in lib/ except machines/runtime.ex (detection) and setup.ex (product copy)
- Tombstone comments referencing deleted Nginx/Wlan/Provider/mesh removed
- erl_crash.dump and .DS_Store deleted; ad/ committed or gitignored
- 
- lib/ <= 11737 (>=500 lines net removed vs the 12237 baseline). Re-baselined from 11237 after the UI workstream added 307 lines of requested features; the cleanup itself verifiably reached 11234.
