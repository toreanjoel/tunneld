defmodule Tunneld.Servers.FakeData.Ai do
  @moduledoc """
  Mock data for the AI assistant in development and test environments.
  """

  @doc """
  Returns a sample AI configuration.
  """
  def get_config do
    %{
      "base_url" => "http://localhost:11434/v1",
      "api_key" => "",
      "model" => "llama3"
    }
  end

  @doc """
  Returns a sample list of available models.
  """
  def get_models do
    [
      %{"id" => "llama3", "object" => "model"},
      %{"id" => "mistral", "object" => "model"},
      %{"id" => "codellama", "object" => "model"}
    ]
  end

  @doc """
  Returns a mock chat completion response. Matches on message content to
  return either a text response or a tool call for testing purposes.
  """
  def chat_completion(messages, _tools) do
    last_message = List.last(messages)
    role = get_in(last_message, ["role"]) || ""
    content = get_in(last_message, ["content"]) || ""
    lower = String.downcase(content)

    # After a tool result, always respond with text to avoid infinite loops
    if role == "tool" do
      tool_followup_response(content)
    else
      cond do
        String.contains?(lower, "wifi") or String.contains?(lower, "scan") ->
          tool_call_response("wifi_scan", %{})

        String.contains?(lower, "restart") ->
          tool_call_response("service_restart", %{"id" => "nginx"})

        String.contains?(lower, "blocklist") ->
          tool_call_response("blocklist_update", %{})

        String.contains?(lower, "device") ->
          text_response(
            "I can see **4 devices** currently connected to your subnet:\n\n" <>
              "- **pi-gateway** (192.168.1.1) — this device\n" <>
              "- **macbook-pro** (192.168.1.42) — active, 2.3 GB today\n" <>
              "- **iphone-14** (192.168.1.55) — active, 340 MB today\n" <>
              "- **smart-tv** (192.168.1.80) — idle since 3h ago\n\n" <>
              "Would you like me to revoke any of these or check their bandwidth usage?"
          )

        String.contains?(lower, "status") or String.contains?(lower, "health") ->
          text_response(
            "Here's your gateway health summary:\n\n" <>
              "- **Internet**: Connected via wlan0 (signal: -42 dBm, excellent)\n" <>
              "- **Tunnel**: zrok share active, public endpoint healthy\n" <>
              "- **DNS**: dnsmasq running, 1,247 queries today, 23% blocked\n" <>
              "- **CPU**: 12% avg — running cool\n" <>
              "- **Memory**: 412 MB / 1 GB (41%)\n" <>
              "- **Storage**: 3.2 GB / 14.4 GB (22%)\n\n" <>
              "Everything looks good. No issues detected."
          )

        String.contains?(lower, "share") or String.contains?(lower, "resource") ->
          text_response(
            "You have **2 public shares** and **1 private share** configured:\n\n" <>
              "**Public:**\n" <>
              "- `home-api` → 192.168.1.1:4000 (enabled, basic auth on)\n" <>
              "- `media-server` → 192.168.1.80:8096 (enabled)\n\n" <>
              "**Private:**\n" <>
              "- `ssh-access` → 192.168.1.1:22 (enabled)\n\n" <>
              "Would you like to add a new share or modify an existing one?"
          )

        String.contains?(lower, "hello") or String.contains?(lower, "hi") or
            String.contains?(lower, "hey") ->
          text_response(
            "Hey! I'm your gateway assistant. I can help you manage WiFi, " <>
              "tunneled shares, DNS, services, and connected devices. What would you like to do?"
          )

        true ->
          text_response(
            "I can help you manage your gateway. Here's what I can do:\n\n" <>
              "- **Scan for WiFi** networks and connect\n" <>
              "- **Manage shares** — add, remove, or toggle public/private resources\n" <>
              "- **Restart services** like nginx, dnsmasq, or dnscrypt-proxy\n" <>
              "- **Update blocklists** for DNS filtering\n" <>
              "- **Check device** connections and bandwidth\n\n" <>
              "Just ask in plain language!"
          )
      end
    end
  end

  defp tool_followup_response(content) do
    lower = String.downcase(content)

    cond do
      String.contains?(lower, "wifi_scan") or String.contains?(lower, "networks") ->
        text_response(
          "Scan complete! Found **6 networks** nearby:\n\n" <>
            "- **HomeNetwork-5G** (signal: -38 dBm) — currently connected\n" <>
            "- **Neighbor_WiFi** (signal: -62 dBm)\n" <>
            "- **CoffeeShop_Free** (signal: -71 dBm)\n" <>
            "- **5G-Router-A1** (signal: -74 dBm)\n\n" <>
            "Your current connection looks strong. Want to switch networks?"
        )

      String.contains?(lower, "restart") or String.contains?(lower, "service") ->
        text_response("Service restarted successfully. It's back online and responding to health checks.")

      true ->
        text_response("Done! The action completed successfully. Is there anything else you'd like me to help with?")
    end
  end

  defp text_response(content) do
    %{
      "choices" => [
        %{
          "message" => %{
            "role" => "assistant",
            "content" => content
          }
        }
      ]
    }
  end

  defp tool_call_response(name, arguments) do
    %{
      "choices" => [
        %{
          "message" => %{
            "role" => "assistant",
            "content" => nil,
            "tool_calls" => [
              %{
                "id" => "call_#{:rand.uniform(100_000)}",
                "type" => "function",
                "function" => %{
                  "name" => name,
                  "arguments" => Jason.encode!(arguments)
                }
              }
            ]
          }
        }
      ]
    }
  end
end
