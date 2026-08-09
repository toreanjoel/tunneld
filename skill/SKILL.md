# Tunneld Agent Skill

Thin Python adapter over the tunneld agent HTTP API. **No policy lives here** —
the HTTP API is the product; this skill only wraps it.

## Prerequisites

- A tunneld gateway reachable at `TUNNELD_URL` (default `http://10.0.0.1`).
- A scoped `tnld_...` bearer token in `TUNNELD_TOKEN`.
  Issue one on the gateway: `mix tunneld.issue_token machines:read,resources:write,exec`

## Module: `tunneld_agent`

```python
from tunneld_agent import TunneldClient

client = TunneldClient(url=os.environ["TUNNELD_URL"], token=os.environ["TUNNELD_TOKEN"])

client.machines()                  # -> {"machines": [...]}
client.machine(id)                 # -> {"machine": {...}}
client.listeners(id)               # -> {"listeners": [...]}
client.probe(id)                   # -> {"job_id": ...}   (202, poll jobs)
client.exec(id, cmd)               # -> {"job_id": ...}
client.jobs(id)                    # -> {"status": "running"|"done", "result": ...}
client.resources()                 # -> {"resources": [...]}
client.add_resource(name, pool)    # -> {"id": ..., "lan_url": ...}
client.rm_resource(id)             # -> {"deleted": id}
```

All methods raise `TunneldError` on 4xx/5xx. Long ops (probe/exec) return a job
id; call `client.jobs(id)` until `status == "done"`.

## Scopes

The token must hold the scope for each call: `machines:read`, `machines:write`,
`resources:read`, `resources:write`, `exec`. The API enforces scopes; the
client does not.
