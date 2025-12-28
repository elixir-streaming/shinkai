defmodule Shinkai.Sink.WebRTC.PeerManager do
  @moduledoc false

  use GenServer

  require Logger

  alias ExWebRTC.PeerConnection

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: opts[:name])
  end

  @spec add_video_track(server :: GenServer.name() | pid(), tuple()) :: :ok
  def add_video_track(manager, track) do
    GenServer.call(manager, {:add_video_track, track})
  end

  @spec add_audio_track(server :: GenServer.name() | pid(), tuple()) :: :ok
  def add_audio_track(manager, track) do
    GenServer.call(manager, {:add_audio_track, track})
  end

  @spec add_peer(server :: GenServer.name() | pid(), from :: GenServer.from()) :: :ok
  def add_peer(manager, from) do
    GenServer.cast(manager, {:add_peer, from})
  end

  @spec handle_peer_answer(
          server :: pid() | atom(),
          from :: GenServer.from(),
          session_id :: String.t(),
          sdp_answer :: String.t()
        ) :: :ok
  def handle_peer_answer(manager, from, session_id, sdp_answer) do
    GenServer.cast(manager, {:handle_peer_answer, from, session_id, sdp_answer})
  end

  @impl true
  def init(opts) do
    {:ok,
     %{
       source_id: opts[:source_id],
       sessions: %{},
       peers: %{},
       video_track: nil,
       audio_track: nil
     }}
  end

  @impl true
  def handle_call({:add_video_track, track}, _from, state) do
    {:reply, :ok, %{state | video_track: track}}
  end

  def handle_call({:add_audio_track, track}, _from, state) do
    {:reply, :ok, %{state | audio_track: track}}
  end

  @impl true
  def handle_cast({:add_peer, from}, state) do
    video_tracks = if state.video_track, do: [elem(state.video_track, 1)], else: []
    audio_tracks = if state.audio_track, do: [elem(state.audio_track, 1)], else: []

    tracks =
      Enum.reject([state.video_track, state.audio_track], &is_nil/1) |> Enum.map(&elem(&1, 0))

    with {:ok, pc} <-
           PeerConnection.start(video_codecs: video_tracks, audio_codecs: audio_tracks),
         :ok <- add_tracks(pc, tracks),
         {:ok, offer} <- PeerConnection.create_offer(pc),
         :ok <- PeerConnection.set_local_description(pc, offer) do
      {:noreply, %{state | peers: Map.put(state.peers, pc, from)}}
    else
      {:error, reason} ->
        GenServer.reply(from, {:error, reason})
        {:noreply, state}
    end
  end

  def handle_cast({:handle_peer_answer, from, session_id, sdp}, state) do
    case Map.fetch(state.sessions, session_id) do
      {:ok, pid} ->
        desc = %ExWebRTC.SessionDescription{
          type: :answer,
          sdp: sdp
        }

        :ok = PeerConnection.set_remote_description(pid, desc)
        GenServer.reply(from, :ok)
        {:noreply, state}

      :error ->
        GenServer.reply(from, {:error, :invalid_session_id})
        {:noreply, state}
    end
  end

  @impl true
  def handle_info({:ex_webrtc, pid, {:ice_gathering_state_change, :complete}}, state) do
    state =
      case Map.pop(state.peers, pid) do
        {nil, peers} ->
          %{state | peers: peers}

        {from, peers} ->
          session_id = UUID.uuid4()
          offer = PeerConnection.get_local_description(pid)
          GenServer.reply(from, {:ok, offer.sdp, session_id})

          %{
            state
            | peers: peers,
              sessions: Map.put(state.sessions, session_id, pid)
          }
      end

    {:noreply, state}
  end

  def handle_info({:ex_webrtc, pid, {:connection_state_change, :connected}}, state) do
    {session_id, pc} = Enum.find(state.sessions, fn {_session_id, p} -> p == pid end)
    Registry.register(Shinkai.Registry, {:webrtc, state.source_id}, {pc, session_id})
    {:noreply, %{state | sessions: Map.delete(state.sessions, session_id)}}
  end

  def handle_info({:ex_webrtc, pid, {:connection_state_change, connection_state}}, state)
      when connection_state in [:failed, :closed, :disconnected] do
    Logger.info("WebRTC PeerConnection #{inspect(pid)} connection state: #{connection_state}")
    PeerConnection.stop(pid)
    Registry.unregister_match(Shinkai.Registry, {:webrtc, state.source_id}, {pid, :_})
    {:noreply, state}
  end

  def handle_info({:ex_webrtc, _pid, {:rtcp, _}}, state) do
    {:noreply, state}
  end

  def handle_info({:ex_webrtc, _pid, msg}, state) do
    Logger.info("Unhandled ExWebRTC message: #{inspect(msg)}")
    {:noreply, state}
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end

  defp add_tracks(pc, tracks) do
    Enum.reduce_while(tracks, :ok, fn track, :ok ->
      case PeerConnection.add_track(pc, track) do
        {:ok, _} -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end
end
