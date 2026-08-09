#!/usr/bin/env python3
"""Tunneld MCP server - one tool per agent API endpoint, no policy.

Speaks the Model Context Protocol over stdio (JSON-RPC 2.0). Each tool maps to
exactly one agent API endpoint; the API (the product) enforces scopes/auth.

Tools:
  tunneld_machines()                 -> GET  /api/v1/agent/machines
  tunneld_machine(id)                -> GET  /api/v1/agent/machines/:id
  tunneld_listeners(id)              -> GET  /api/v1/agent/machines/:id/listeners
  tunneld_probe(id)                  -> POST /api/v1/agent/machines/:id/probe   (job)
  tunneld_exec(id, cmd)              -> POST /api/v1/agent/machines/:id/exec     (job)
  tunneld_jobs(id)                   -> GET  /api/v1/agent/jobs/:id
  tunneld_resources()                -> GET  /api/v1/agent/resources
  tunneld_add_resource(name, pool)   -> POST /api/v1/agent/resources
  tunneld_rm_resource(id)            -> DELETE /api/v1/agent/resources/:id

Env: TUNNELD_URL (default http://10.0.0.1), TUNNELD_TOKEN (scoped tnld_ token).
"""
import json
import os
import sys
import urllib.request
import urllib.error

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from tunneld_agent import TunneldClient, TunneldError


class MCPError(Exception):
    pass


def _rpc(id, method, params):
    return {"jsonrpc": "2.0", "id": id, "method": method, "params": params}


def _tools_definition():
    client = None  # tools are static; client created per call
    def tool(name, description, schema, handler):
        return {"name": name, "description": description, "inputSchema": schema}

    return [
        tool("tunneld_machines", "List managed machines.", {"type": "object", "properties": {}}, None),
        tool("tunneld_machine", "Fetch one machine.", {"type": "object", "properties": {"id": {"type": "string"}}, "required": ["id"]}, None),
        tool("tunneld_listeners", "List listening sockets on a machine.", {"type": "object", "properties": {"id": {"type": "string"}}, "required": ["id"]}, None),
        tool("tunneld_probe", "Probe a machine (returns a job id; poll tunneld_jobs).", {"type": "object", "properties": {"id": {"type": "string"}}, "required": ["id"]}, None),
        tool("tunneld_exec", "Run a command on a machine (returns a job id).", {"type": "object", "properties": {"id": {"type": "string"}, "cmd": {"type": "string"}}, "required": ["id", "cmd"]}, None),
        tool("tunneld_jobs", "Fetch a job result.", {"type": "object", "properties": {"id": {"type": "string"}}, "required": ["id"]}, None),
        tool("tunneld_resources", "List resources.", {"type": "object", "properties": {}}, None),
        tool("tunneld_add_resource", "Create a resource from a backend pool.", {"type": "object", "properties": {"name": {"type": "string"}, "pool": {"type": "array", "items": {"type": "string"}}}, "required": ["name", "pool"]}, None),
        tool("tunneld_rm_resource", "Remove a resource by id.", {"type": "object", "properties": {"id": {"type": "string"}}, "required": ["id"]}, None),
    ]


def _make_client():
    try:
        return TunneldClient()
    except TunneldError as e:
        raise MCPError(str(e))


def _call_tool(client, name, args):
    args = args or {}
    if name == "tunneld_machines":
        return client.machines()
    if name == "tunneld_machine":
        return client.machine(args["id"])
    if name == "tunneld_listeners":
        return client.listeners(args["id"])
    if name == "tunneld_probe":
        return client.probe(args["id"])
    if name == "tunneld_exec":
        return client.exec(args["id"], args["cmd"])
    if name == "tunneld_jobs":
        return client.jobs(args["id"])
    if name == "tunneld_resources":
        return client.resources()
    if name == "tunneld_add_resource":
        return client.add_resource(args["name"], args["pool"])
    if name == "tunneld_rm_resource":
        return client.rm_resource(args["id"])
    raise MCPError("unknown tool: " + name)


def main():
    tools = _tools_definition()
    client = _make_client()
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            req = json.loads(line)
        except json.JSONDecodeError:
            continue
        rid = req.get("id")
        method = req.get("method", "")

        if method == "initialize":
            out = _rpc(rid, "initialize", {"protocolVersion": "2024-11-05", "capabilities": {"tools": {}}, "serverInfo": {"name": "tunneld", "version": "0.1"}})
        elif method == "tools/list":
            out = _rpc(rid, "tools/list", {"tools": tools})
        elif method == "tools/call":
            params = req.get("params", {})
            name = params.get("name", "")
            args = params.get("arguments", {})
            try:
                result = _call_tool(client, name, args)
                content = [{"type": "text", "text": json.dumps(result)}]
                out = _rpc(rid, "tools/call", {"content": content, "isError": False})
            except (MCPError, TunneldError, KeyError) as e:
                content = [{"type": "text", "text": str(e)}]
                out = _rpc(rid, "tools/call", {"content": content, "isError": True})
        else:
            out = _rpc(rid, method, {})
        sys.stdout.write(json.dumps(out) + "\n")
        sys.stdout.flush()


if __name__ == "__main__":
    main()
