defmodule Tunneld.Ai.SystemPromptTest do
  use ExUnit.Case, async: true

  alias Tunneld.Ai.SystemPrompt

  describe "build/0" do
    test "returns a non-empty string" do
      prompt = SystemPrompt.build()
      assert is_binary(prompt)
      assert String.length(prompt) > 0
    end

    test "includes tool descriptions" do
      prompt = SystemPrompt.build()
      assert prompt =~ "wifi_scan"
      assert prompt =~ "service_restart"
      assert prompt =~ "blocklist_update"
    end

    test "includes gateway context" do
      prompt = SystemPrompt.build()
      assert prompt =~ "Tunneld"
      assert prompt =~ "gateway"
    end

    test "includes safety rules" do
      prompt = SystemPrompt.build()
      assert prompt =~ "destructive"
      assert prompt =~ "confirmation"
    end
  end
end
