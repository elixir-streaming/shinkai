defmodule Shinkai.Sink.WebRTC.PeerManager do
  @moduledoc false

  use GenServer

  require Logger

  alias ExWebRTC.PeerConnection

  @h264_codec %ExWebRTC.RTPCodecParameters{
    payload_type: 96,
    mime_type: "video/H264",
    clock_rate: 90_000,
    sdp_fmtp_line: %ExSDP.Attribute.FMTP{
      pt: 96,
      level_asymmetry_allowed: true,
      packetization_mode: 1,
      profile_level_id: 0x42E01F
    }
  }

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: opts[:name])
  end

  @spec add_peer(server :: pid() | atom(), from :: GenServer.from()) :: :ok
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
    {:ok, %{source_id: opts[:source_id], sessions: %{}, peers: %{}}}
  end

  @impl true
  def handle_cast({:add_peer, from}, state) do
    stream_id = ExWebRTC.MediaStreamTrack.generate_stream_id()
    video_track = ExWebRTC.MediaStreamTrack.new(:video, [stream_id])

    with {:ok, pc} <- PeerConnection.start(video_codecs: [@h264_codec]),
         {:ok, _} <- PeerConnection.add_track(pc, video_track),
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

  def handle_info({:ex_webrtc, pid, {:ice_connection_state_change, :connected}}, state) do
    {session_id, pc} = Enum.find(state.sessions, fn {_session_id, p} -> p == pid end)
    Registry.register(Shinkai.Registry, {:webrtc, state.source_id}, {pc, session_id})
    {:noreply, %{state | sessions: Map.delete(state.sessions, session_id)}}
  end

  def handle_info({:ex_webrtc, _pid, {:ice_connection_state_change, :failed}}, state) do
    # Handle failed connection
    {:noreply, state}
  end

  def handle_info({:ex_webrtc, _pid, msg}, state) do
    Logger.info("Unhandled ExWebRTC message: #{inspect(msg)}")
    {:noreply, state}
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end
end
