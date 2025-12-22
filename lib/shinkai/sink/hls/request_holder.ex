defmodule Shinkai.Sink.Hls.RequestHolder do
  @moduledoc false

  use GenServer

  def start_link(name) do
    GenServer.start_link(__MODULE__, nil, name: name)
  end

  @spec hold(pid() | atom(), integer(), non_neg_integer(), non_neg_integer()) :: :ok
  def hold(holder, variant_id, seg, part) do
    GenServer.call(holder, {:hold, variant_id, seg, part}, 2_000)
  end

  @impl true
  def init(_) do
    {:ok, %{segment_idx: 0, part_idx: 0, clients: %{}}}
  end

  @impl true
  def handle_call({:hold, _variant_id, seg, part}, _from, state)
      when seg < state.segment_idx or (seg == state.segment_idx and part <= state.part_idx) do
    {:reply, :ok, state}
  end

  @impl true
  def handle_call({:hold, variant_id, seg, part}, from, state) do
    clients = Map.update(state.clients, {variant_id, seg, part}, [from], &[from | &1])
    {:noreply, %{state | clients: clients}}
  end

  @impl true
  def handle_info({:hls_part, variant_id, seg, part}, state) do
    {pids, clients} = Map.pop(state.clients, {variant_id, seg, part}, [])
    for pid <- pids, do: GenServer.reply(pid, :ok)
    {:noreply, %{state | clients: clients, segment_idx: seg, part_idx: part}}
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end
end
