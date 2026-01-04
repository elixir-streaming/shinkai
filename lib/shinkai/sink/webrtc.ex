defmodule Shinkai.Sink.WebRTC do
  @moduledoc false

  use GenServer

  require Logger

  import Shinkai.Utils

  alias __MODULE__.PeerManager
  alias ExWebRTC.RTPCodecParameters
  alias Phoenix.PubSub
  alias RTSP.RTP.Encoder, as: RTPEncoder

  @supported_codecs [:h264, :h265, :pcma]
  @video_clock_rate 90_000

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

  @spec remove_peer(server :: pid() | atom(), session_id :: String.t()) :: :ok
  def remove_peer(server, session_id) do
    GenServer.cast(server, {:remove_peer, session_id})
  end

  @impl true
  def init(opts) do
    source_id = opts[:id]
    {:ok, peer_manager} = PeerManager.start_link(source_id: source_id)

    PubSub.subscribe(Shinkai.PubSub, tracks_topic(source_id))

    {:ok,
     %{
       peer_manager: peer_manager,
       source_id: source_id,
       packets_topic: packets_topic(source_id),
       tracks: %{}
     }}
  end

  @impl true
  def handle_call(:add_new_peer, _from, %{video_tracks: [], audio_tracks: []} = state) do
    {:reply, {:error, :no_tracks}, state}
  end

  def handle_call(:add_new_peer, from, state) do
    :ok = PeerManager.add_peer(state.peer_manager, from)
    {:noreply, state}
  end

  def handle_call({:handle_peer_answer, session_id, sdp}, from, state) do
    :ok = PeerManager.handle_peer_answer(state.peer_manager, from, session_id, sdp)
    {:noreply, state}
  end

  @impl true
  def handle_cast({:remove_peer, session_id}, state) do
    :ok = PeerManager.remove_peer(state.peer_manager, session_id)
    {:noreply, state}
  end

  @impl true
  def handle_info({:tracks, tracks}, state) do
    {tracks, unsupported_tracks} = Enum.split_with(tracks, &(&1.codec in @supported_codecs))

    if unsupported_tracks != [] do
      Logger.warning(
        "Unsupported codecs received in WebRTC sink: #{join_codecs(unsupported_tracks)}"
      )
    end

    video_track = Enum.find(tracks, fn t -> t.type == :video end)
    audio_track = Enum.find(tracks, fn t -> t.type == :audio end)

    stream_id = ExWebRTC.MediaStreamTrack.generate_stream_id()

    state =
      [video_track, audio_track]
      |> Enum.reject(&is_nil/1)
      |> Enum.reduce(state, fn track, state ->
        media_stream = ExWebRTC.MediaStreamTrack.new(track.type, [stream_id])
        webrtc_track = webrtc_track(track)

        payloader_mod = payloader_mod(track.codec)

        track_ctx = %{
          id: media_stream.id,
          timescale: track.timescale,
          target_timescale: webrtc_track.clock_rate,
          payloader_mod: payloader_mod,
          payloader_state: payloader_mod.init([])
        }

        if track.type == :video,
          do: PeerManager.add_video_track(state.peer_manager, {media_stream, webrtc_track}),
          else: PeerManager.add_audio_track(state.peer_manager, {media_stream, webrtc_track})

        %{state | tracks: Map.put(state.tracks, track.id, track_ctx)}
      end)

    :ok = PubSub.subscribe(Shinkai.PubSub, state.packets_topic)

    {:noreply, state}
  end

  @impl true
  def handle_info({:packet, packets}, state) when is_list(packets) do
    track_id = hd(packets).track_id

    case(Map.fetch(state, track_id)) do
      :error ->
        {:noreply, state}

      {:ok, track_ctx} ->
        track_ctx =
          Enum.reduce(packets, track_ctx, fn packet, track_ctx ->
            do_handle_packet(packet, state.source_id, track_ctx)
          end)

        {:noreply, %{state | tracks: Map.put(state.tracks, track_id, track_ctx)}}
    end
  end

  def handle_info({:packet, packet}, state) do
    case Map.fetch(state.tracks, packet.track_id) do
      :error ->
        {:noreply, state}

      {:ok, track_ctx} ->
        track_ctx = do_handle_packet(packet, state.source_id, track_ctx)
        {:noreply, %{state | tracks: Map.put(state.tracks, packet.track_id, track_ctx)}}
    end
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end

  defp do_handle_packet(packet, source_id, track_ctx) do
    rtp_timestamp =
      ExMP4.Helper.timescalify(packet.pts, track_ctx.timescale, track_ctx.target_timescale)

    {packets, payloader_state} =
      track_ctx.payloader_mod.handle_sample(
        packet.data,
        rtp_timestamp,
        track_ctx.payloader_state
      )

    track_id = track_ctx.id

    Registry.dispatch(Shinkai.Registry, {:webrtc, source_id}, fn peers ->
      for {_pid, {pc, _session_id}} <- peers do
        Enum.each(packets, fn rtp_packet ->
          :ok = ExWebRTC.PeerConnection.send_rtp(pc, track_id, rtp_packet)
        end)
      end
    end)

    %{track_ctx | payloader_state: payloader_state}
  end

  defp webrtc_track(track) do
    pt = payload_type(track.codec)

    %RTPCodecParameters{
      payload_type: pt,
      mime_type: mime_type(track.codec),
      clock_rate: clock_rate(track),
      channels: if(track.type == :audio, do: 1, else: nil),
      sdp_fmtp_line: sdp_fmtp_line(track.codec, pt)
    }
  end

  defp clock_rate(%{type: :video}), do: @video_clock_rate
  defp clock_rate(%{timescale: timescale}), do: timescale

  defp payload_type(:pcma), do: 8
  defp payload_type(_codec), do: 96

  defp mime_type(:h264), do: "video/H264"
  defp mime_type(:h265), do: "video/H265"
  defp mime_type(:pcma), do: "audio/PCMA"

  defp sdp_fmtp_line(:h264, pt) do
    %ExSDP.Attribute.FMTP{
      pt: pt,
      level_asymmetry_allowed: true,
      packetization_mode: 1,
      profile_level_id: 0x42E01F
    }
  end

  defp sdp_fmtp_line(:h265, _pt), do: nil
  defp sdp_fmtp_line(_codec, _pt), do: nil

  defp payloader_mod(:h264), do: RTPEncoder.H264
  defp payloader_mod(:h265), do: RTPEncoder.H265
  defp payloader_mod(:pcma), do: RTPEncoder.G711
end
