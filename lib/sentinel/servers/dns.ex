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
    {:ok, %{socket: socket}}
  end

  # Handles incoming UDP messages
  def handle_info(
        {:udp, _socket, ip, port, data},
        %{socket: socket} = state
      ) do
    # Decode the incoming DNS query using the DNS.Record.decode function
    case DNS.Record.decode(data) do
      # If decoding is successful, proceed with extracting the header and question (qd)
      %DNS.Record{header: header, qdlist: [%DNS.Query{domain: domain}]} ->
        # Convert domain list to a single string (e.g., ["example", "com"] becomes "example.com")
        domain_str = domain |> to_string()

        IO.inspect(domain_str, label: "Domain String")
        IO.inspect(Sentinel.Servers.Blacklist.get_all(), label: "Blacklist")

        # Check if the domain is in the blacklist
        if Enum.member?(Sentinel.Servers.Blacklist.get_all(), domain_str) do
          # If blacklisted, respond with NXDOMAIN (non-existent domain)
          send_response(socket, ip, port, header.id, {:error, :nxdomain, domain_str})
        else
          # Otherwise, resolve the domain to an IP address
          case DNS.resolve(domain) do
            # If successful, get the first answer record's IP and send as response
            {:ok, [ip]} ->
              send_response(socket, ip, port, header.id, {:ok, ip, domain_str})

            # If resolution fails, respond with NXDOMAIN
            _ ->
              send_response(socket, ip, port, header.id, {:error, :nxdomain, domain_str})
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
  # Sends an NXDOMAIN response if the domain is blacklisted or resolution fails
  defp send_response(socket, ip, port, id, {:error, :nxdomain, domain}) do
    response =
      DNS.Record.encode(%DNS.Record{
        # 3 – NXDomain
        header: build_header(id, 3),
        qdlist: [
          %DNS.Query{
            domain: to_charlist(domain),
            # internet
            class: :in,
            # A record
            type: :a
          }
        ],
        # No answer list for NXDOMAIN
        anlist: [],
        # No additional records
        arlist: [],
        # No nameserver records
        nslist: []
      })

    # Log details for debugging
    Logger.debug("Sending NXDOMAIN for domain: #{domain}")
    Logger.debug("DNS NXDOMAIN Response: #{inspect(response)}")
    :gen_udp.send(socket, ip, port, response)
  end

  # Sends a successful response with the resolved IP address
  defp send_response(socket, ip, port, id, {:ok, ip_address, domain}) do
    response =
      DNS.Record.encode(%DNS.Record{
        header: build_header(id, 0),
        # If there are queries you need to respond to, they go here
        qdlist: [],
        anlist: [
          %DNS.Resource{
            domain: to_charlist(domain),
            # internet
            class: :in,
            # ipv4 - A record
            type: :a,
            # time to live in seconds
            ttl: 300,
            data: ip_address
          }
        ],
        # Additional records can go here if needed
        arlist: [],
        nslist: []
      })

    # Detailed logs on the request and response
    Logger.debug("DNS Query: #{inspect(domain)}")
    Logger.debug("DNS Response: #{inspect(response)}")
    Logger.debug("DNS Response IP: #{inspect(ip_address)}")
    Logger.debug("DNS Response Domain: #{inspect(domain)}")
    Logger.debug("DNS Response ID: #{inspect(id)}")
    :gen_udp.send(socket, ip, port, response)
  end

  # Define a helper function to build the DNS Header
  # rcode is the response code
  # 0 – NoError: Success, meaning the query was processed without errors.
  # 1 – FormErr: Format error, indicating the query was not understood by the server.
  # 2 – ServFail: Server failure, which implies the server was unable to process the request due to an internal issue.
  # 3 – NXDomain: Non-existent domain, meaning the domain does not exist in the server's DNS records.
  # 4 – NotImp: Not implemented, used if the server does not support the requested operation.
  # 5 – Refused: Query refused, which means the server refuses to respond to the query.
  defp build_header(id, rcode) when rcode in [0, 1, 2, 3, 4, 5] do
    %DNS.Header{
      id: id,
      qr: true,
      opcode: :query,
      aa: false,
      tc: false,
      rd: true,
      ra: false,
      rcode: rcode
    }
  end
end
