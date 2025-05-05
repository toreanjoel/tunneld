defmodule Sentinel.Servers.Notification do
  @moduledoc """
  The notification server that will manage the notifications that need to be setup.
  """

  use GenServer
  require Logger

  @interface Application.compile_env!(:sentinel, [:network, :wlan])

  @broadcast_topic_main "component:notifications"
  @interval 30_000

  @spec start_link(any()) :: GenServer.on_start()
  def start_link(_) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @doc """
  Init setup notification settings
  """
  @spec init(any()) :: {:ok, map()}
  def init(_) do
    if not file_exists?(), do: create_file()

    # Start overview trigger
    send(self(), :sync)
    {:ok, %{}}
  end

  @doc """
  Update and manage the changes to the notification settings file
  """
  def handle_call(
        {:update_settings, %{"endpoint" => _endpoint, "enabled" => _enabled} = data},
        _,
        state
      ) do
    # Here we need to update the file and also send off the relevant notifcations to the client
    case File.write(path(), Jason.encode!(data)) do
      :ok ->
        Phoenix.PubSub.broadcast(Sentinel.PubSub, "notifications", %{
          type: :info,
          message: "Successfully updated notification settings"
        })

        # Update the dashboard view nodes
        broadcast_settings()

        {:reply, {:ok, data}, state}

      {:error, err} ->
        Phoenix.PubSub.broadcast(Sentinel.PubSub, "notifications", %{
          type: :error,
          message: "Failed to update notification settings: #{inspect(err)}"
        })

        {:error, "Failed to update notification settings: #{inspect(err)}"}

        {:reply, {:error, %{}}, state}
    end
  end

  @doc """
  The trigger that will be a cast that the notification server will send to the endpoint
  """
  def handle_cast({:trigger, style, msg}, state) do
    %{"enabled" => enabled, "endpoint" => endpoint} = fetch_settings()

    # We need to make sure things are e
    if enabled and endpoint !== "" do
      post(:transient, endpoint, %{
        type: "alert",
        style: style |> to_string,
        message: msg,
        duration: 10000
      })
    end

    {:noreply, state}
  end

  @doc """
  The interval that will be sending the overview
  """
  def handle_info(:sync, state) do
    %{"enabled" => enabled, "endpoint" => endpoint} = fetch_settings()

    if enabled and endpoint !== "" do
      # this is for development data as the env wont contain the same functions of the prod env
      if Application.get_env(:sentinel, :mock_data, false) do
        %{cpu: cpu, mem: mem_percent, storage: storage_percent} =
          Sentinel.Servers.Resources.get_resources()

        post(:overview, endpoint, %{
          type: "overview",
          data: %{
            cpu: cpu |> to_string,
            ram: mem_percent |> to_string,
            storage: storage_percent |> to_string,
            ip: %{lan: "DEVELOP", wan: "DEVELOP"},
            uptime: "DEVELOP"
          }
        })
      else
        # We make sure we are enabled with regards to sending out notifications
        if enabled and endpoint !== "" do
          # uptime - we remove the up and only get the rest of the data
          {"up " <> uptime, 0} = System.cmd("uptime", ["-p"])

          # The custom uptime formatted data
          uptime = uptime
          |> String.trim()
          |> String.split(", ")
          |> Enum.map(&shorten/1)
          |> Enum.join(" ")

          # lan
          {lan_ip, 0} = System.cmd("sh", ["-c", "hostname -I | awk '{print $1}'"])
          # raw ip
          {ip_raw, 0} =
            System.cmd("sh", [
              "-c",
              "ip -4 addr show #{@interface} | grep -oP '(?<=inet\\s)\\d+(\\.\\d+){3}'"
            ])

          %{cpu: cpu, mem: mem_percent, storage: storage_percent} =
            Sentinel.Servers.Resources.get_resources()

          post(:overview, endpoint, %{
            type: "overview",
            data: %{
              # devices: %{count: 100, max: 6},
              # tunnels: %{active: 2, total: 3},
              # services: %{ok: 4, total: 4},
              cpu: cpu |> to_string,
              ram: mem_percent |> to_string,
              storage: storage_percent |> to_string,
              ip: %{lan: String.trim(lan_ip), wan: String.trim(ip_raw)},
              uptime: String.trim(uptime)
            }
          })
        end
      end
    end

    # Start the sync process again
    sync_overview()

    {:noreply, state}
  end

  @doc """
  Read the notification file
  """
  @spec read_file() :: {:ok, map()} | {:error, String.t()}
  def read_file() do
    case path() |> File.read() do
      {:ok, data} ->
        case Jason.decode(data) do
          {:ok, data} ->
            {:ok, data}

          {:error, err} ->
            {:error, "Failed to decode notification file: #{inspect(err)}"}
        end

      {:error, reason} ->
        {:error, "There was a problem reading the file: #{inspect(reason)}"}
    end
  end

  @doc """
  Create the notification file
  """
  @spec create_file() :: {:ok, String.t()} | {:error, String.t()}
  def create_file() do
    case path()
         |> File.write(
           Jason.encode!(%{
             "endpoint" => "",
             "enabled" => false
           })
         ) do
      :ok ->
        {:ok, "Notification settings file created"}

      {:error, reason} ->
        {:error, "Failed to create notification file: #{inspect(reason)}"}
    end
  end

  @doc """
  Calling functions that will be able to interact with the gen server
  NOTE: All system alerts will be of type alert, this server sends the overview
  """
  def trigger({:info, msg}) do
    GenServer.cast(__MODULE__, {:trigger, :info, msg})
  end

  def trigger({:warning, msg}) do
    GenServer.cast(__MODULE__, {:trigger, :warning, msg})
  end

  def trigger({:critical, msg}) do
    GenServer.cast(__MODULE__, {:trigger, :critical, msg})
  end

  @doc """
  Get the relevant settings for notifications
  """
  def fetch_settings() do
    {_, data} = read_file()
    data
  end

  @doc """
  The setup functions that will update the settings of the notification settings
  """
  def update_settings(settings) do
    GenServer.call(__MODULE__, {:update_settings, settings}, 30_000)
  end

  @doc """
  Check if the notification file exists
  """
  @spec file_exists?() :: boolean()
  def file_exists?(), do: path() |> File.exists?()

  # Broadcast the nodes to the relevant component
  defp broadcast_settings() do
    settings = fetch_settings()

    # Broadcast to the live view (or parent) so it can update the notification settings component.
    # Use an id that matches the one used in your live_component render.
    Phoenix.PubSub.broadcast(Sentinel.PubSub, @broadcast_topic_main, %{
      id: "notifications",
      module: SentinelWeb.Live.Components.Nodes,
      data: settings
    })

    settings
  end

  # HTTP post to the stored endpoing
  # We let the system crash if the trigger is not a suppeorted type
  defp post(:transient, endpoint, data) do
    # We make sure we encode the data before sending it
    encoded_data = Jason.encode!(data)

    case HTTPoison.post(endpoint, encoded_data, [{"Content-Type", "application/json"}]) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        :ok

      _ ->
        Logger.error("There was an error sending the notifcation")
    end
  end

  # The overview that will be sent at a certain interval
  defp post(:overview, endpoint, data) do
    # We make sure we encode the data before sending it
    encoded_data = Jason.encode!(data)

    case HTTPoison.post(endpoint, encoded_data, [{"Content-Type", "application/json"}]) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        :ok

      _ ->
        Logger.error("There was an error sending the notifcation")
    end
  end

  # Take string data from the response of System.cmd("uptime", ["-p"]) and make it nicer to read
  defp shorten(segment) do
    cond do
      String.contains?(segment, "day") ->
        segment |> String.replace(" days", "d") |> String.replace(" day", "d")

      String.contains?(segment, "hour") ->
        segment |> String.replace(" hours", "h") |> String.replace(" hour", "h")

      String.contains?(segment, "minute") ->
        segment |> String.replace(" minutes", "m") |> String.replace(" minute", "m")

      true ->
        segment
    end
  end

  # The job that will start interval sync
  defp sync_overview() do
    :timer.send_after(@interval, :sync)
  end

  # Path helper
  @spec path() :: String.t()
  defp path(), do: "./" <> config_fs(:root) <> config_fs(:notifications)

  # Config helper
  @spec config_fs() :: keyword()
  defp config_fs(), do: Application.get_env(:sentinel, :fs)

  @spec config_fs(atom()) :: any()
  defp config_fs(key), do: config_fs()[key]
end
