defmodule Mix.Tasks.Tunneld.IssueToken do
  @shortdoc "Issue a scoped agent API token (operator action; never via the API)"
  @moduledoc """
  Issue a scoped `tnld_...` agent API bearer token.

  Token issuance is deliberately NOT exposed via the API (it is a forbidden
  scope). The operator runs this on the gateway to mint a token with the
  given scopes, then distributes it to agents.

      mix tunneld.issue_token machines:read,resources:write

  Scopes are comma-separated. Reserved scopes (token issuance, machine
  enrollment, iptables admin, dns provider, wireguard keys) are stripped.
  """
  use Mix.Task

  @impl true
  def run(args) do
    scopes =
      args
      |> Enum.flat_map(&String.split(&1, ","))
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))

    # Ensure the app (and thus the AgentTokens GenServer) is running so the
    # token is persisted to the configured data dir.
    Application.ensure_all_started(:tunneld)

    case Tunneld.AgentTokens.issue(scopes) do
      {:ok, raw, _id, granted} ->
        IO.puts("")
        IO.puts("=== Agent token ===")
        IO.puts("TOKEN: #{raw}")
        IO.puts("SCOPES: #{Enum.join(granted, ", ")}")
        IO.puts("")

        IO.puts(
          "Use: curl -H 'Authorization: Bearer #{raw}' http://<gateway>/api/v1/agent/machines"
        )

        IO.puts("")

      _ ->
        IO.puts("Failed to issue token")
        exit({:shutdown, 1})
    end
  end
end
