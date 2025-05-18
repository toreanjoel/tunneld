defmodule SentinelWeb.SentinetChannel do
  @moduledoc """
  The channel and how we handle the connection on joins and custom topics
  """
  use SentinelWeb, :channel

  @impl true
  def join("sentinet", payload, socket) do
    if authorized?(payload) do
      {:ok, socket}
    else
      {:error, %{reason: "Unable to connect"}}
    end
  end

  # Channels can be used in a request/response fashion
  # by sending replies to requests from the client
  @impl true
  def handle_in("ping", payload, socket) do
    {:reply, {:ok, payload}, socket}
  end

  # It is also common to receive messages from the client and
  # broadcast to everyone in the current topic (sentinet:lobby).
  @impl true
  def handle_in("shout", payload, socket) do
    broadcast(socket, "shout", payload)
    {:noreply, socket}
  end

  @doc """
  Handle different types of event payloads
  """
  @impl true
  def handle_in("event", %{"type" => "init"}, socket) do
    # init the data for the user
    {:reply, {:ok, init_data()}, socket}
  end
  def handle_in("event", payload, socket) do
    IO.inspect(payload)
    {:reply, {:ok, "MSG"}, socket}
  end

  # Add authorization logic here as required.
  defp authorized?(%{"token" => token}) do
    if Sentinel.Servers.Encryption.fetch_settings() === token do
      true
    else
      false
    end
  end
  defp authorized?(_) do
    false
  end

  # Here we send the init date to the new user
  defp init_data do
    # Get relevant data here to the client
    %{
      "data" => "This is the init data!"
    }
  end
end
