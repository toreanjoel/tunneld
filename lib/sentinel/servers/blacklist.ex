defmodule Sentinel.Servers.Blacklist do
  @moduledoc """
  Manage blacklist domains
  """
  use GenServer
  require Logger

  @interval 30_000
  @topic "sentinel:blacklist"
  # we also have a system blacklist but this they dont change for now
  @path System.user_home() <> "/blacklists/dnsmasq-user.blacklist"

  def start_link(_) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @doc """
  Init blacklist
  """
  def init(_) do
    send(self(), :sync)
    {:ok, %{
      count: count_blacklist()
    }}
  end

  @doc """
  Get all of the information around blacklist
  Note: for now the user needs to get everything
  """
  def handle_call(:get_state, _from, state) do
    {:reply, {:ok, state}, state}
  end

  # Here we get the list of domains based off page
  def handle_call({:get_blacklist_page, offset, limit}, _from, state) do
    result = fetch_blacklist(offset, limit)
    check_ahead = fetch_blacklist(offset + limit, limit)

    # We check if there is more data ahead
    result = %{
      data: result,
      has_more_data: !Enum.empty?(check_ahead),
      curr_page: offset,
    }

    {:reply, {:ok, result}, state}
  end

  # get the data and restart sync
  def handle_info(:sync, state) do
    # TODO: Here we get the logs and also any specific information we want to broadcast i.e count of blacklist
    # THIS IS NOT GOOD, WE NEED A BETTER WAY TO TRACK COUNT
    result = %{
      count: count_blacklist(),
    }

    Phoenix.PubSub.broadcast(Sentinel.PubSub, @topic, {:blacklist_info, result})

    # Refetch
    sync_blacklist()

    {:noreply, Map.merge(state, result)}
  end

  # The job that will start interval sync
  defp sync_blacklist() do
    :timer.send_after(@interval, :sync)
  end

  # we fetch the user blacklist file data
  defp fetch_blacklist(offset, limit) do
    if Application.get_env(:sentinel, :mock_data, false) do
      Sentinel.Servers.FakeData.Blacklist.get_data()
    else
      try do
        File.stream!(@path)
        |> Stream.drop(offset)
        |> Stream.take(limit)
        |> Enum.to_list()
      rescue
        _ ->
          []
      end
    end |> clean_data()
  end

  # we will remove the syntax from the file as we only need the domains
  defp clean_data(data) do
    data
    |> Enum.map(fn item ->
      item
      # Remove "local=/"
      |> String.trim_leading("local=/")
      # Remove "/\n"
      |> String.trim_trailing("/\n")
    end)
  end

  # we count the number of lines in the blacklist file
  def count_blacklist() do
    try do
      if Application.get_env(:sentinel, :mock_data, false) do
        Sentinel.Servers.FakeData.Blacklist.get_data() |> length
      else
        File.stream!(@path)
        |> Enum.reduce(0, fn _, acc -> acc + 1 end)
      end
    rescue
      _ ->
        0
    end
  end

  # Get entire state details for the blacklist
  def get_state(), do: GenServer.call(__MODULE__, :get_state)
  def get_blacklist_page(offset, limit), do: GenServer.call(__MODULE__, {:get_blacklist_page, offset, limit})
end
