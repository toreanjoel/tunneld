defmodule Iptables do
  @moduledoc """
  Module that will contain helper functions to interact with the firewall rules
  """

  @doc """
  Add iptables entry - with user mac address
  """
  def add_user_entry(ip, mac) do
    System.cmd("iptables", [
      "-t",
      "mangle",
      "-I",
      "PREROUTING",
      "-m",
      "mac",
      "--mac-source",
      mac,
      "-d",
      ip,
      "-j",
      "DROP"
    ])
  end

  def remove_user_entry(ip, mac) do
    System.cmd("iptables", [
      "-t",
      "mangle",
      "-D",
      "PREROUTING",
      "-m",
      "mac",
      "--mac-source",
      mac,
      "-d",
      ip,
      "-j",
      "DROP"
    ])
  end

  @doc """
  Add iptables entry - system wide entry
  """
  def add_system_entry(ip) do
    System.cmd("iptables", [
      "-t",
      "mangle",
      "-I",
      "PREROUTING",
      "-d",
      ip,
      "-j",
      "DROP"
    ])
  end

  def remove_system_entry(ip) do
    System.cmd("iptables", [
      "-t",
      "mangle",
      "-D",
      "PREROUTING",
      "-d",
      ip,
      "-j",
      "DROP"
    ])
  end

  @doc """
  Check the existence of the iptables entry
  """
  def has_user_entry?(ip, mac) do
    System.cmd("iptables", [
      "-t",
      "mangle",
      "-C",
      "PREROUTING",
      "-m",
      "mac",
      "--mac-source",
      mac,
      "-d",
      ip,
      "-j",
      "DROP"
    ])
  end

  @doc """
  Check the existence of the iptables entry
  """
  def has_system_entry?(ip) do
    System.cmd("iptables", [
      "-t",
      "mangle",
      "-C",
      "PREROUTING",
      "-d",
      ip,
      "-j",
      "DROP"
    ])
  end

  @doc """
  Flush the iptables - remove all entries
  """
  def flush() do
    System.cmd("iptables", [
      "-t",
      "mangle",
      "-F",
      "PREROUTING"
    ])
  end
end
