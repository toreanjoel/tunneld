defmodule Sentinel.Servers.DNSListener do
  use GenServer

  @listen_port 53  # Standard DNS port
  @allowed_domains [""]  # Add your allowed domains here

  # Start the GenServer
  def start_link(_) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  # Initialize the server, open the UDP socket to listen for incoming DNS requests
  def init(state) do
    # Open a UDP socket on the specified port
    {:ok, socket} = :gen_udp.open(@listen_port, [:binary, active: false, ip: {0, 0, 0, 0}])

    IO.puts("DNS Listener started on port #{@listen_port}")

    # Store the socket in the state and continue to listen for requests
    {:ok, %{socket: socket}, {:continue, :listen}}
  end

  # Continue listening for incoming DNS requests
  def handle_continue(:listen, state) do
    listen_for_requests(state.socket)
    {:noreply, state}
  end

  # Listen for DNS requests and handle them accordingly
  defp listen_for_requests(socket) do
    spawn(fn ->
      # Wait indefinitely to receive a DNS request over the socket
      case :gen_udp.recv(socket, 512, :infinity) do
        {:ok, {client_ip, client_port, packet}} ->
          # Extract the domain name from the request
          domain = parse_domain_name(packet)

          # Log the domain name
          IO.puts("Received DNS request from #{inspect(client_ip)}:#{client_port} for domain: #{domain}")

          # Check if the domain is allowed
          allowed = Enum.any?(@allowed_domains, fn allowed_domain ->
            String.ends_with?(domain, allowed_domain)
          end)

          if allowed do
            IO.puts("Domain #{domain} is allowed. Forwarding request.")
            # Forward the request to an external DNS server and get the response
            response = forward_request(packet)
            # Send the response back to the client
            :gen_udp.send(socket, client_ip, client_port, response)
          else
            IO.puts("Domain #{domain} is not allowed. Blocking request.")
            # Send a blocking response back to the client
            response = block_request(packet)
            :gen_udp.send(socket, client_ip, client_port, response)
          end

          # Continue listening for the next request
          listen_for_requests(socket)

        {:error, reason} ->
          IO.puts("Failed to receive request: #{inspect(reason)}")
          listen_for_requests(socket)
      end
    end)
  end

  # Parse the domain name from the DNS request packet
  defp parse_domain_name(packet) do
    <<_header::binary-size(12), rest::binary>> = packet
    {domain, _rest} = parse_labels(rest)
    domain
  end

  # Helper function to parse the labels (domain parts)
  defp parse_labels(<<0, rest::binary>>) do
    {"", rest}
  end

  defp parse_labels(<<len, rest::binary>>) when len > 0 do
    <<label::binary-size(len), rest::binary>> = rest
    {next_labels, rest} = parse_labels(rest)
    domain_part = if next_labels == "", do: label, else: label <> "." <> next_labels
    {domain_part, rest}
  end

  defp parse_labels(_), do: {"", ""}

  # Forward the DNS request to an external DNS server and return the response
  defp forward_request(packet) do
    # Open a UDP socket to the external DNS server
    {:ok, udp_socket} = :gen_udp.open(0, [:binary, active: false])
    # Send the packet to the external DNS server
    external_dns_server_ip = {1, 1, 1, 1}  # Google DNS
    external_dns_port = 53
    :gen_udp.send(udp_socket, external_dns_server_ip, external_dns_port, packet)
    # Wait for the response
    case :gen_udp.recv(udp_socket, 512, 5000) do
      {:ok, {_ip, _port, response}} ->
        # Close the socket
        :gen_udp.close(udp_socket)
        response
      {:error, reason} ->
        IO.puts("Failed to receive response from external DNS server: #{inspect(reason)}")
        # Close the socket
        :gen_udp.close(udp_socket)
        # Return a blocking response
        block_request(packet)
    end
  end

  # Build a SERVFAIL response to block the request
  defp block_request(packet) do
    # Extract the transaction ID from the request
    <<transaction_id::binary-size(2), _rest::binary>> = packet

    # Set the flags to indicate SERVFAIL error
    flags = <<0x81, 0x83>>  # QR=1, OpCode=0, AA=0, TC=0, RD=1, RA=0, Z=0, RCODE=3 (Name Error)

    # Construct the response header:
    # - Transaction ID from the request
    # - Flags set to SERVFAIL
    # - Questions, Answer RRs, Authority RRs, Additional RRs all set to 0
    header = transaction_id <> flags <> <<0x00, 0x00, 0x00, 0x00, 0x00, 0x00>>

    # Append the original Question section from the request
    <<_transaction_id::binary-size(2), _flags::binary-size(2), qdcount::binary-size(2), _rest::binary>> = packet

    # If there's at least one question, include it in the response
    question_section = if qdcount != <<0x00, 0x00>> do
      <<_header::binary-size(12), question::binary>> = packet
      question
    else
      ""
    end

    response_packet = header <> question_section

    # Log the response packet for verification
    IO.inspect(response_packet, label: "Blocking response (SERVFAIL)")

    response_packet
  end
end
