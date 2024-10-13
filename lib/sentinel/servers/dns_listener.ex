defmodule Sentinel.Servers.DNSListener do
  use GenServer

  @listen_port 53  # Standard DNS port

  # Start the GenServer
  def start_link(_) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  # Initialize the server, open the UDP socket to listen for incoming DNS requests
  def init(state) do
    # Open a UDP socket on the specified port
    {:ok, socket} = :gen_udp.open(@listen_port, [:binary, active: false])

    IO.puts("DNS Listener started on port #{@listen_port}")

    # Store the socket in the state and continue to listen for requests
    {:ok, %{socket: socket}, {:continue, :listen}}
  end

  # Continue listening for incoming DNS requests
  def handle_continue(:listen, state) do
    listen_for_requests(state.socket)
    {:noreply, state}
  end

  # Listen for DNS requests and block every request
  defp listen_for_requests(socket) do
    spawn(fn ->
      # Wait indefinitely to receive a DNS request over the socket
      case :gen_udp.recv(socket, 512, :infinity) do
        {:ok, {client_ip, client_port, packet}} ->
          # Log incoming raw packet data
          IO.puts("Received DNS request from #{inspect(client_ip)}:#{client_port}")
          IO.inspect(packet, label: "Raw packet received")

          # Respond with a SERVFAIL to block the request
          response = block_request(packet)

          # Send the SERVFAIL response back to the client over the UDP socket
          :gen_udp.send(socket, client_ip, client_port, response)

          # Continue listening for the next request
          listen_for_requests(socket)

        {:error, reason} ->
          IO.puts("Failed to receive request: #{inspect(reason)}")
          listen_for_requests(socket)
      end
    end)
  end

  # Build a SERVFAIL response to block the request
  defp block_request(packet) do
    # Extract the transaction ID from the request
    <<transaction_id::binary-size(2), _rest::binary>> = packet

    # Set the flags to indicate SERVFAIL error
    flags = <<0x81, 0x82>>  # QR=1, RD=1, RA=1, SERVFAIL (RCODE=2)

    # Construct the response header:
    # - Transaction ID from the request
    # - Flags set to SERVFAIL
    # - 0x00, 0x01: Number of Questions = 1
    # - 0x00, 0x00: Number of Answer RRs = 0
    # - 0x00, 0x00: Number of Authority RRs = 0
    # - 0x00, 0x00: Number of Additional RRs = 0
    header = transaction_id <> flags <> <<0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00>>

    # Append the original Question section from the request
    <<_transaction_id::binary-size(2), rest::binary>> = packet
    response_packet = header <> rest

    # Log the response packet for verification
    IO.inspect(response_packet, label: "Blocking response (SERVFAIL)")

    response_packet
  end
end
