defmodule Tunneld.Servers.DeviceTagsTest do
  use ExUnit.Case, async: false

  alias Tunneld.Servers.DeviceTags

  @mac "aa:bb:cc:dd:ee:ff"
  @mac2 "11:22:33:44:55:66"

  setup do
    # Clean up any existing tags file before each test
    path = Path.join(Tunneld.Config.fs_root(), "device_tags.json")
    File.rm(path)
    File.rm(path <> ".bak")
    :ok
  end

  describe "add_tag/2" do
    test "adds a tag to a device" do
      :ok = DeviceTags.add_tag(@mac, "living-room")
      assert DeviceTags.get_tags(@mac) == ["living-room"]
    end

    test "adds multiple tags to a device" do
      :ok = DeviceTags.add_tag(@mac, "IoT")
      :ok = DeviceTags.add_tag(@mac, "camera")
      tags = DeviceTags.get_tags(@mac)
      assert "IoT" in tags
      assert "camera" in tags
      assert length(tags) == 2
    end

    test "ignores duplicate tags" do
      :ok = DeviceTags.add_tag(@mac, "work")
      :ok = DeviceTags.add_tag(@mac, "work")
      assert DeviceTags.get_tags(@mac) == ["work"]
    end

    test "trims whitespace from tags" do
      :ok = DeviceTags.add_tag(@mac, "  office  ")
      assert DeviceTags.get_tags(@mac) == ["office"]
    end

    test "ignores empty tags" do
      :ok = DeviceTags.add_tag(@mac, "")
      assert DeviceTags.get_tags(@mac) == []
    end
  end

  describe "remove_tag/2" do
    test "removes a tag from a device" do
      :ok = DeviceTags.add_tag(@mac, "tag1")
      :ok = DeviceTags.add_tag(@mac, "tag2")
      :ok = DeviceTags.remove_tag(@mac, "tag1")
      assert DeviceTags.get_tags(@mac) == ["tag2"]
    end

    test "removes device entry when last tag is removed" do
      :ok = DeviceTags.add_tag(@mac, "only-tag")
      :ok = DeviceTags.remove_tag(@mac, "only-tag")
      assert DeviceTags.get_tags(@mac) == []
      assert DeviceTags.all_tags() == %{}
    end

    test "is no-op for nonexistent tag" do
      :ok = DeviceTags.add_tag(@mac, "tag1")
      :ok = DeviceTags.remove_tag(@mac, "nonexistent")
      assert DeviceTags.get_tags(@mac) == ["tag1"]
    end
  end

  describe "get_tags/1" do
    test "returns empty list for unknown device" do
      assert DeviceTags.get_tags(@mac) == []
    end
  end

  describe "all_tags/0" do
    test "returns all device tags" do
      :ok = DeviceTags.add_tag(@mac, "living-room")
      :ok = DeviceTags.add_tag(@mac2, "work-laptop")

      all = DeviceTags.all_tags()
      assert "living-room" in all[@mac]
      assert "work-laptop" in all[@mac2]
    end

    test "returns empty map when no tags exist" do
      assert DeviceTags.all_tags() == %{}
    end
  end

  describe "persistence" do
    test "tags survive module reload" do
      :ok = DeviceTags.add_tag(@mac, "persistent")

      # Simulate reload by reading fresh
      assert DeviceTags.get_tags(@mac) == ["persistent"]
    end

    test "tags persist across operations on different devices" do
      :ok = DeviceTags.add_tag(@mac, "tag-a")
      :ok = DeviceTags.add_tag(@mac2, "tag-b")
      :ok = DeviceTags.remove_tag(@mac, "tag-a")

      assert DeviceTags.get_tags(@mac) == []
      assert DeviceTags.get_tags(@mac2) == ["tag-b"]
    end
  end
end
