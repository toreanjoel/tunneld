defmodule Sentinel.Servers.DNS do
  @moduledoc """
  This module is responsible for handling DNS requests.
  """
  use GenServer
  require Logger

  # Default port for the DNS server
  @port 53

  # Starts the GenServer process
  def start_link(_) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  # Initializes the server, opens a UDP socket on port 53, and sets up the initial state
  def init(_) do
    # Open a UDP socket on port 53 (DNS default) with binary mode and reusable address options
    {:ok, socket} = :gen_udp.open(@port, [:binary, active: true, reuseaddr: true])

    blacklist = Sentinel.Servers.Blacklist.get_all()

    # Store the socket and an example blacklist in the state
    {:ok, %{socket: socket, blacklist: blacklist}}
  end

  # Handles incoming UDP messages
  def handle_info({:udp, _socket, ip, port, data}, %{socket: socket, blacklist: blacklist} = state) do
    # Decode the incoming DNS query using the DNS.Record.decode function
    case DNS.Record.decode(data) do
      # If decoding is successful, proceed with extracting the header and question (qd)
      {:ok, %{header: header, qd: [%{domain: domain}]}} ->

        # Convert domain list to a single string (e.g., ["example", "com"] becomes "example.com")
        domain_str = Enum.join(domain, ".")

        # Check if the domain is in the blacklist
        if Map.has_key?(blacklist, domain_str) do
          # If blacklisted, respond with NXDOMAIN (non-existent domain)
          send_response(socket, ip, port, header.id, :nxdomain)
        else
          # Otherwise, resolve the domain to an IP address
          case DNS.resolve(domain, :in, :a) do
            # If successful, get the first answer record's IP and send as response
            {:ok, %{an: [%{data: ip} | _]}} ->
              send_response(socket, ip, port, header.id, {:ok, ip})

            # If resolution fails, respond with NXDOMAIN
            _ ->
              send_response(socket, ip, port, header.id, :nxdomain)
          end
        end

      # If decoding fails, log a warning
      _ ->
        Logger.debug("Failed to decode DNS query")
    end

    # Continue without changing state
    {:noreply, state}
  end

  # Sends an NXDOMAIN response if the domain is blacklisted or resolution fails
  defp send_response(socket, ip, port, id, :nxdomain) do
    # Build a DNS response struct with NXDOMAIN code
    response = DNS.Record.encode(%{header: %{id: id, qr: true, rcode: :nxdomain}})

    # Send the encoded response over UDP to the original requester
    :gen_udp.send(socket, ip, port, response)
  end

  # Sends a successful response with the resolved IP address
  defp send_response(socket, ip, port, id, {:ok, ip_address}) do
    # Build a DNS response struct containing the IP address
    response = DNS.Record.encode(%{
      header: %{id: id, qr: true},
      an: [%{domain: "example.com", class: :in, type: :a, data: ip_address}]
    })

    # Send the encoded response over UDP to the original requester
    :gen_udp.send(socket, ip, port, response)
  end
end
