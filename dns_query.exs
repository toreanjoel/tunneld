defmodule DNSQuery do
  @moduledoc """
  Module to perform a DNS query for an A record.

  This module builds a DNS query packet for a given domain and sends it to a public DNS server
  (e.g., Google's DNS server at 8.8.8.8). The DNS server then returns an IP address for the queried domain.
  """

  # We could use cloudflare as well so either 1.1.1.1 or 1.0.0.1 or 8.8.8.8 - this could be configuraable
  @dns_server {8, 8, 8, 8} # Google's Public DNS server
  @dns_port 53
  @query_id <<0x12, 0x34>> # 16-bit identifier for the query

  @doc """
  Converts a domain (e.g., "example.com") to DNS format with length-prefixed segments.

  ## Explanation
  DNS requests encode the domain name in a specific format, where each part of the domain
  is prefixed with its length. The entire domain is terminated with a null byte (<<0>>).

  For example, "example.com" becomes `<<7, "example", 3, "com", 0>>`:

  - "example" has 7 characters, so it's represented as <<7>> <> "example"
  - "com" has 3 characters, so it's represented as <<3>> <> "com"
  - The null byte (<<0>>) denotes the end of the domain name.

  ## Parameters
  - `domain` - The domain name to convert to DNS format (e.g., "example.com").

  ## Returns
  - A binary representing the domain name in DNS query format.
  """
  defp format_domain(domain) do
    # Split domain, prepend length bytes, then join with an empty string, finally add null byte
    formatted_domain =
      domain
      |> String.split(".")
      |> Enum.map(fn part -> <<byte_size(part)>> <> part end)
      |> Enum.join("")

    formatted_domain <> <<0>>
  end

  @doc """
  Constructs a DNS query packet with a header and question section.

  ## Explanation
  The query packet consists of:
  - **Header**: 12 bytes, including the query ID, flags, and section counts.
  - **Question**: Includes the formatted domain, type, and class.

  The query is constructed as:
  - `@query_id`: 2 bytes for a unique identifier.
  - Flags: 2 bytes for the query type (standard query with recursion).
  - Question Count: 2 bytes set to 1, indicating one question in the query.
  - Answer, Authority, and Additional Records Counts: 2 bytes each, set to 0 for a simple query.
  - Question Section:
    - Formatted Domain: Using `format_domain/1`.
    - Type A (0x0001): Specifies an IPv4 address request.
    - Class IN (0x0001): Specifies the Internet class.

  ## Parameters
  - `domain` - The domain to query (e.g., "example.com").

  ## Returns
  - A binary representing the DNS query packet.
  """
  def build_query(domain) do
    # Header: ID, Flags, Questions, Answer RRs, Authority RRs, Additional RRs
    header = @query_id <> <<0x01, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00>>
    question = format_domain(domain) <> <<0x00, 0x01, 0x00, 0x01>> # Type A, Class IN
    header <> question
  end

  @doc """
  Sends a DNS query packet to a public DNS server and retrieves the response.

  ## Explanation
  - Opens a UDP socket to send and receive data.
  - Builds the query packet using `build_query/1`.
  - Sends the query to the configured DNS server and waits for a response.
  - Parses the response using `parse_response/1`.

  ## Parameters
  - `domain` - The domain name to query (e.g., "example.com").

  ## Returns
  - The parsed DNS response, or an error if the query fails.
  """
  def send_query(domain) do
    {:ok, socket} = :gen_udp.open(0, [:binary, active: false])

    # Build and send the DNS query
    query_packet = build_query(domain)
    :ok = :gen_udp.send(socket, @dns_server, @dns_port, query_packet)

    # Receive the response
    case :gen_udp.recv(socket, 512, 5000) do
      {:ok, {_from, _port, response}} ->
        IO.puts("Received response: #{inspect(response)}")
        :gen_udp.close(socket)
        parse_response(response)

      {:error, reason} ->
        IO.puts("Failed to receive response: #{inspect(reason)}")
        :gen_udp.close(socket)
        {:error, reason}
    end
  end

  @doc """
  Parses a DNS response (simplified) to show the returned data.

  ## Explanation
  - Extracts the data from the response by skipping the header.
  - This example decodes and displays the binary data in hexadecimal format.
  - For a fully functional DNS resolver, additional parsing of the response is needed.

  ## Parameters
  - `response` - The raw binary DNS response from the DNS server.

  ## Returns
  - The parsed response data, displayed in hexadecimal.
  """
  defp parse_response(response) do
    <<_header::binary-size(12), question_and_answer::binary>> = response
    IO.puts("Response Data: #{Base.encode16(question_and_answer)}")
  end
end

# Test the module by querying example.com
DNSQuery.send_query("google.com")
