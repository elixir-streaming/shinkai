defmodule Shinkai.Sink.WebRTC do
  @moduledoc false

  use GenServer

  alias __MODULE__.PeerManager

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: opts[:name])
  end

  @spec add_new_peer(server :: pid() | atom()) :: {:ok, String.t(), String.t()} | {:error, any()}
  def add_new_peer(server) do
    GenServer.call(server, :add_new_peer)
  end

  @spec handle_peer_answer(
          server :: pid() | atom(),
          session_id :: String.t(),
          sdp :: String.t()
        ) :: :ok | {:error, any()}
  def handle_peer_answer(server, session_id, sdp) do
    GenServer.call(server, {:handle_peer_answer, session_id, sdp})
  end

  @impl true
  def init(opts) do
    {:ok, peer_manager} = PeerManager.start_link(source_id: opts[:id])
    {:ok, %{peer_manager: peer_manager, source_id: opts[:id]}}
  end

  @impl true
  def handle_call(:add_new_peer, from, state) do
    :ok = PeerManager.add_peer(state.peer_manager, from)
    {:noreply, state}
  end

  def handle_call({:handle_peer_answer, session_id, sdp}, from, state) do
    :ok = PeerManager.handle_peer_answer(state.peer_manager, from, session_id, sdp)
    {:noreply, state}
  end
end
