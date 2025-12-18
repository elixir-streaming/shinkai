defmodule Shinkai.Sources.PublishManager do
  @moduledoc false
  # Since publishers (like rtmp) are managed by the server (e.g. rtmp server).
  # We'll have this gen server monitors the source and stop/delete the source once
  # the publisher dies.

  require Logger

  use GenServer

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @spec monitor(Shinkai.Sources.Source.t(), pid()) :: :ok
  def monitor(source, pid) do
    GenServer.call(__MODULE__, {:monitor, source, pid})
  end

  @impl true
  def init(_opts) do
    Logger.debug("Starting PublishManager")
    {:ok, %{}}
  end

  @impl true
  def handle_call({:monitor, source, pid}, _from, state) do
    Logger.debug("Monitoring publisher source #{source.id} with pid #{inspect(pid)}")
    ref = Process.monitor(pid)
    {:reply, :ok, Map.put(state, ref, source)}
  end

  @impl true
  def handle_info({:DOWN, ref, :process, _pid, _reason}, state) do
    Logger.debug("Publisher process down, stopping source")

    case Map.pop(state, ref) do
      {nil, _state} ->
        {:noreply, state}

      {source, new_state} ->
        Shinkai.Sources.stop(source.id, true)
        {:noreply, new_state}
    end
  end
end
