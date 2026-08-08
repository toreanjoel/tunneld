defmodule Tunneld.Schema.ContainerTest do
  use ExUnit.Case, async: true

  alias Tunneld.Schema.Container

  test "image field is a curated dropdown with a sensible default" do
    schema = Container.data(%{})
    image = schema["properties"]["image"]

    assert image["type"] == "string"
    assert image["default"] == "images:debian/12"
    assert "images:debian/12" in image["ui:enum"]
    assert "images:debian/11" in image["ui:enum"]
    assert "images:alpine/3.21" in image["ui:enum"]
    assert "custom" in image["ui:enum"]
    # image must NOT be a validation enum, so custom values pass validation
    refute Map.has_key?(image, "enum")
  end

  test "image is required" do
    schema = Container.data(%{})
    assert "image" in schema["required"]
  end
end
