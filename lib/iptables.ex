defmodule Iptables do
  @moduledoc """
  Module that will contain helper functions to interact with the firewall rules
  """

  @doc """
  Add iptables entry - with user mac address
  """
  def add_user_entry(ip, mac_addr, :insert) do
    System.cmd("iptables", [
      "-t",
      "mangle",
      "-I",
      "PREROUTING",
      "-m",
      "mac",
      "--mac-source",
      mac_addr,
      "-d",
      ip,
      "-j",
      "DROP"
    ])
  end

  def remove_user_entry(ip, mac_addr, :remove) do
    System.cmd("iptables", [
      "-t",
      "mangle",
      "-D",
      "PREROUTING",
      "-m",
      "mac",
      "--mac-source",
      mac_addr,
      "-d",
      ip,
      "-j",
      "DROP"
    ])
  end

  @doc """
  Add iptables entry - system wide entry
  """
  def add_system_entry(ip, :insert) do
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

  def remove_system_entry(ip, :remove) do
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
  def has_user_entry?(ip, mac_addr) do
    System.cmd("iptables", [
      "-t",
      "mangle",
      "-C",
      "PREROUTING",
      "-m",
      "mac",
      "--mac-source",
      mac_addr,
      "-d",
      ip,
      "-j",
      "DROP"
    ])
  end

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
end
