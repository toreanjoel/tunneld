defmodule TunneldWeb.Live.Components.Obfuscation do
  @moduledoc """
  Small helper for dashboard obfuscation. Returns masked text when active.
  """

  def mask(true, _value), do: "••••••"
  def mask(false, value), do: to_string(value)
  def mask(nil, value), do: to_string(value)
end
