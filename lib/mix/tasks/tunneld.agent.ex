defmodule Mix.Tasks.Tunneld.Agent do
  @shortdoc "tunneld CLI - thin HTTP wrapper over the agent API"
  @moduledoc """
  Thin CLI over the tunneld agent HTTP API (no policy; the API is the product).

      mix tunneld.agent <command> [args...]

  Commands:
    machines                          GET  /agent/machines
    machine <id>                      GET  /agent/machines/:id
    listeners <id>                    GET  /agent/machines/:id/listeners
    probe <id>                        POST /agent/machines/:id/probe  (202 job)
    exec <id> <cmd>                   POST /agent/machines/:id/exec   (202 job)
    job <id>                          GET  /agent/jobs/:id
    resources                         GET  /agent/resources
    add-resource <name> <pool...>     POST /agent/resources
    rm-resource <id>                  DELETE /agent/resources/:id

  Env:
    TUNNELD_URL  (default http://10.0.0.1)
    TUNNELD_TOKEN (required; scoped tnld_ bearer token)
  """
  use Mix.Task

  @impl true
  def run(args) do
    base = System.get_env("TUNNELD_URL") || "http://10.0.0.1"
    token = System.get_env("TUNNELD_TOKEN")

    if is_nil(token) do
      IO.puts("TUNNELD_TOKEN required (issue via: mix tunneld.issue_token machines:read,resources:write)")
      exit({:shutdown, 1})
    end

    {result, _code} = dispatch(base, token, args)

    IO.puts(Jason.encode!(result, pretty: true))

    if is_map(result) and Map.get(result, "error") do
      exit({:shutdown, 1})
    end
  end

  defp dispatch(base, token, [cmd | rest]) do
    case cmd do
      "machines" -> api(base, token, :get, "/api/v1/agent/machines")
      "machine" -> api(base, token, :get, "/api/v1/agent/machines/#{hd(rest)}")
      "listeners" -> api(base, token, :get, "/api/v1/agent/machines/#{hd(rest)}/listeners")
      "probe" -> api(base, token, :post, "/api/v1/agent/machines/#{hd(rest)}/probe")
      "exec" -> api(base, token, :post, "/api/v1/agent/machines/#{hd(rest)}/exec", %{"cmd" => Enum.join(tl(rest), " ")})
      "job" -> api(base, token, :get, "/api/v1/agent/jobs/#{hd(rest)}")
      "resources" -> api(base, token, :get, "/api/v1/agent/resources")
      "add-resource" ->
        [name | pool] = rest
        api(base, token, :post, "/api/v1/agent/resources", %{"name" => name, "pool" => pool})
      "rm-resource" -> api(base, token, :delete, "/api/v1/agent/resources/#{hd(rest)}")
      _ -> {{%{"error" => "unknown command: #{cmd}"}, :json}}
    end
  end

  defp dispatch(_base, _token, []), do: {{%{"error" => "usage: tunneld.agent <command> [args]"}, :json}}

  defp api(base, token, method, path, body \\ nil) do
    url = base <> path
    headers = [{"authorization", "Bearer #{token}"}, {"content-type", "application/json"}]

    result =
      case method do
        :get -> HTTPoison.get(url, headers)
        :post -> HTTPoison.post(url, Jason.encode!(body || %{}), headers)
        :delete -> HTTPoison.delete(url, headers)
      end

    case result do
      {:ok, %HTTPoison.Response{status_code: s, body: b}} ->
        case Jason.decode(b) do
          {:ok, decoded} -> {decoded, :json}
          _ -> {{%{"status" => s, "body" => b}}, :json}
        end

      {:error, reason} ->
        {{%{"error" => inspect(reason)}, :json}}
    end
  end
end
