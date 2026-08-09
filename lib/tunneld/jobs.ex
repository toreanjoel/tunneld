defmodule Tunneld.Jobs do
  @moduledoc """
  Long-running job registry for the agent API.

  Operations that can block for tens of seconds (probe, WG install, exec)
  return `202 {job_id}` and are run in a Task; the client polls
  `GET /api/v1/jobs/:id`. This keeps HTTP requests from blocking on slow SSH
  round-trips. State is in-memory (jobs are not expected to survive a restart).
  """

  use GenServer

  def start_link(_), do: GenServer.start_link(__MODULE__, %{}, name: __MODULE__)

  @impl true
  def init(_), do: {:ok, %{}}

  @doc """
  Enqueue a job. `fun` is a `0 -> result` thunk. Returns `{job_id, pid}`.
  The result is stored under `job_id` when the task completes.
  """
  def enqueue(fun) when is_function(fun, 0) do
    GenServer.call(__MODULE__, {:enqueue, fun})
  end

  @doc "Fetch a job by id. Returns `{:ok, %{status, result}}` or `:not_found`."
  def get(id) do
    GenServer.call(__MODULE__, {:get, id})
  end

  @impl true
  def handle_call({:enqueue, fun}, _from, state) do
    id = System.unique_integer([:positive]) |> to_string()
    pid = spawn(fn -> run(id, fun) end)
    state = Map.put(state, id, %{status: :running, result: nil, pid: pid})
    {:reply, {id, pid}, state}
  end

  @impl true
  def handle_call({:get, id}, _from, state) do
    reply =
      case Map.get(state, id) do
        nil -> :not_found
        job -> {:ok, job}
      end

    {:reply, reply, state}
  end

  defp run(id, fun) do
    result =
      try do
        {:ok, fun.()}
      rescue
        e -> {:error, Exception.message(e)}
      catch
        kind, reason -> {:error, "#{kind}: #{inspect(reason)}"}
      end

    GenServer.cast(__MODULE__, {:complete, id, result})
  end

  @impl true
  def handle_cast({:complete, id, result}, state) do
    state = Map.update(state, id, %{status: :done, result: result}, fn job ->
      Map.merge(job, %{status: :done, result: result})
    end)

    {:noreply, state}
  end
end
