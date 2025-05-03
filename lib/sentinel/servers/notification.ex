defmodule Sentinel.Servers.Notification do
  @moduledoc """
  The notification server that will manage the notifications that need to be setup.

  TODO:

  The system should allow for:
  - Notification gets added to a list
  - If it is crucial, it will be added to the top of the list
  - If it is not, it will be added to the end
  - The system will trigger the moment the list is added to
  - it will go through all of the items in the list
  - The duration sent with the notification will also be the pause that will take before the system sends
   - - This time will be sent to the hardware as well and it will also manage
  - If the notification is crucial, it will not wait for a time (if there is another before, it will just send it)
  """

  use GenServer
  require Logger

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
  The trigger that will be a cast that the notification server will send to the endpoint
  """
  def handle_cast({:trigger, style, msg}, state) do

    # TODO: Here we need check if the settings are setup
    # TOOD: we need to check if the notification settings is set as enabled
    # TODO: we need to post to the stored endpoing

    post(:transient, style, %{
      type: "transient",
      style: style |> to_string,
      message: msg,
      duration: 10000
    })

    {:noreply, state}
  end

  @doc """
  Update and manage the changes to the notification settings file
  """
  def handle_cast({:update_settings, %{ endpoint: _endpoint, enabled: _enabled} = data}, state) do
    # Here we need to update the file and also send off the relevant notifcations to the client
    IO.inspect(data, label: "THE UPDATED SETTINGS")

    {:noreply, state}
  end

  @doc """
  The interval that will be sending the overview
  """
  def handle_info(:sync, state) do
    # Get all the details we want to send as part of the overview
    # TODO: replace the information below with actual information

    post(:overview, %{
      type: "overview",
      data: %{
        devices: %{count: 1, max: 6},
        tunnels: %{active: 2, total: 3},
        services: %{ok: 4, total: 4},
        ip: %{lan: "10.0.0.1", wan: "192.168.1.105"},
        uptime: "1d 2h"
      }
    })

    # Start the sync process again
    sync_overview()

    {:noreply, state}
  end

  @doc """
  Read the notification file
  """
  @spec read_file() :: {:ok, map()} | {:error, String.t()}
  def read_file() do
    case path() |> File.read do
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
      |> File.write(Jason.encode!(
        %{
          "endpoint" => "",
          "enabled" => false
        }
      )) do
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
  def trigger({ :info, msg }) do
    GenServer.cast(__MODULE__, {:trigger, :info, msg})
  end
  def trigger({ :warning, msg }) do
    GenServer.cast(__MODULE__, {:trigger, :warning, msg})
  end
  def trigger({ :critical, msg }) do
    GenServer.cast(__MODULE__, {:trigger, :critical, msg})
  end

  @doc """
  The setup functions that will update the settings of the notification settings
  """
  def update_settings() do
    GenServer.cast(__MODULE__, :update_settings)
  end

  @doc """
  Check if the notification file exists
  """
  @spec file_exists?() :: boolean()
  def file_exists?(), do: path() |> File.exists?

  # HTTP post to the stored endpoing
  # We let the system crash if the trigger is not a suppeorted type
  defp post(:transient, style, data) when style in [:critical, :info, :warning] do
    # We make sure we encode the data before sending it
    encoded_data = Jason.encode!(data)

    # Post to the relevant endpoint
    # Get the data from the file i.e endpoint
    endpoint = "FROM_FILE"

    case HTTPoison.post(endpoint, encoded_data, [{"Content-Type", "application/json"}]) do
      {:ok, %HTTPoison.Response{ status_code: 200, body: body }} ->
        IO.inspect(body, label: "SUCESS ALERT")
        # TODO: This would be where we would have sent the data to relevant device
      _ ->
        Logger.error("There was an error sending the notifcation")
    end
  end

  # The overview that will be sent at a certain interval
  defp post(:overview, data) do
    # We make sure we encode the data before sending it
    encoded_data = Jason.encode!(data)

    # Post to the relevant endpoint
    # Get the data from the file i.e endpoint
    endpoint = "http://10.0.0.67/update"

    case HTTPoison.post(endpoint, encoded_data, [{"Content-Type", "application/json"}]) do
      {:ok, %HTTPoison.Response{ status_code: 200, body: body }} ->
        IO.inspect(body, label: "SUCESS")
        # TODO: This would be where we would have sent the data to relevant device
      _ ->
        Logger.error("There was an error sending the notifcation")
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
