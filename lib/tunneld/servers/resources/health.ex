defmodule Tunneld.Servers.Resources.Health do
  @moduledoc """
  Pool health checking for resource backends.

  Checks TCP connectivity to each `IP:port` entry in a resource's pool
  and returns aggregate health status (:all_up, :partial, :none, :empty).
  """

  @doc """
  Check the health of a pool of backend servers.

  Returns a map with `:status`, `:total`, and `:up` keys.
  In mock mode, returns `%{status: :mock, total: n, up: nil}`.
  """
  def pool_health(pool, true) when is_list(pool) do
    %{status: :mock, total: length(pool), up: nil}
  end

  def pool_health(pool, false) when is_list(pool) do
    totals =
      pool
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))
      |> Enum.reduce(%{total: 0, up: 0}, fn entry, acc ->
        case String.split(entry, ":", parts: 2) do
          [ip, port_str] ->
            total = acc.total + 1

            up =
              case Integer.parse(port_str) do
                {port, _} ->
                  if backend_up?(ip, port), do: acc.up + 1, else: acc.up

                _ ->
                  acc.up
              end

            %{acc | total: total, up: up}

          _ ->
            acc
        end
      end)

    status =
      cond do
        totals.total == 0 -> :empty
        totals.up == 0 -> :none
        totals.up == totals.total -> :all_up
        true -> :partial
      end

    Map.put(totals, :status, status)
  end

  def pool_health(_, _), do: %{status: :empty, total: 0, up: 0}

  defp backend_up?(ip, port) do
    case :gen_tcp.connect(String.to_charlist(ip), port, [:binary, active: false], 1500) do
      {:ok, socket} ->
        :gen_tcp.close(socket)
        true

      _ ->
        false
    end
  end
end
