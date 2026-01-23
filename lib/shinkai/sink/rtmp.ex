defmodule Shinkai.Sink.RTMP do
  @moduledoc """
  Module describing an RTMP sink.

  The module is responsible for converting received packets into FLV tags and forward them to clients.
  """

  use GenServer

  require Logger

  import Shinkai.Utils

  alias ExFLV.Tag.{AudioData, ExVideoData, Serializer, VideoData}
  alias ExRTMP.Server.ClientSession
  alias Phoenix.PubSub

  @timescale 1000
  @supported_codesc [:h264, :h265, :av1, :aac, :pcma, :pcmu]

  def start_link(opts) do
    name = {:via, Registry, {Source.Registry, {:rtmp_sink, opts[:id]}}}
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  def add_client(server, pid) do
    GenServer.call(server, {:add_client, pid})
  end

  @impl true
  def init(opts) do
    {id, _rtmp_config} = Keyword.pop!(opts, :id)

    :ok = PubSub.subscribe(Shinkai.PubSub, tracks_topic(id))
    :ok = PubSub.subscribe(Shinkai.PubSub, state_topic(id))

    {:ok, %{source_id: id, tracks: %{}, init_tags: [], packet_topic: packets_topic(id)}}
  end

  @impl true
  def handle_call({:add_client, pid}, _from, state) do
    for {track_id, tag} <- state.init_tags do
      case state.tracks[track_id].type do
        :video -> ClientSession.send_video_data(pid, 0, tag)
        :audio -> ClientSession.send_audio_data(pid, 0, tag)
      end
    end

    {:reply, :ok, state}
  end

  @impl true
  def handle_info({:tracks, tracks}, state) do
    {supported_tracks, unsupported_tracks} =
      Enum.split_with(tracks, &(&1.codec in @supported_codesc))

    if unsupported_tracks != [] do
      Logger.warning(
        "[#{state.source_id}] rtmp sink: ignore unsupported tracks: #{Enum.map_join(unsupported_tracks, ", ", & &1.codec)}"
      )
    end

    init_tags =
      Enum.reduce(supported_tracks, %{}, fn track, acc ->
        case Shinkai.Track.to_rtmp_tag(track) do
          nil -> acc
          tag -> Map.put(acc, track.id, Serializer.serialize(tag))
        end
      end)

    if supported_tracks != [] do
      :ok = PubSub.subscribe(Shinkai.PubSub, state.packet_topic)
    end

    {:noreply, %{state | tracks: Map.new(supported_tracks, &{&1.id, &1}), init_tags: init_tags}}
  end

  @impl true
  def handle_info({:packet, packets}, state) do
    Registry.dispatch(Sink.Registry, {:rtmp, state.source_id}, fn entries ->
      packets = List.wrap(packets)

      case state.tracks[hd(packets).track_id] do
        nil ->
          :ok

        track ->
          dispatch_packets(entries, packets, track)
      end
    end)

    {:noreply, state}
  end

  @impl true
  def handle_info(:disconnected, state) do
    Logger.warning("[#{state.source_id}] [RTMP Sink] source disconnected")

    Registry.dispatch(Sink.Registry, {:rtmp, state.source_id}, fn entries ->
      for {pid, _} <- entries do
        send(pid, :exit)
      end
    end)

    {:noreply, state}
  end

  defp dispatch_packets(entries, packets, track) do
    tags = Enum.map(packets, &packet_to_tag(track, &1))

    for {pid, _} <- entries, {timestamp, data} <- tags do
      # credo:disable-for-next-line
      case track.type do
        :video -> ClientSession.send_video_data(pid, timestamp, data)
        :audio -> ClientSession.send_audio_data(pid, timestamp, data)
      end
    end
  end

  defp packet_to_tag(track, packet) do
    dts = div(packet.dts * @timescale, track.timescale)
    cts = div((packet.pts - packet.dts) * @timescale, track.timescale)

    tag =
      case track.codec do
        :h264 ->
          maybe_prefix_payload(:h264, packet.data)
          |> VideoData.AVC.new(:nalu, cts)
          |> VideoData.new(:h264, if(packet.sync?, do: :keyframe, else: :interframe))

        :aac ->
          packet.data
          |> AudioData.AAC.new(:raw)
          |> AudioData.new(:aac, 1, 3, :stereo)

        codec when codec in [:h265, :av1] ->
          packet_type = if codec == :h265 and cts != 0, do: :coded_frames, else: :coded_frames_x

          %ExVideoData{
            codec_id: codec,
            frame_type: if(packet.sync?, do: :keyframe, else: :interframe),
            packet_type: packet_type,
            composition_time_offset: cts,
            data: maybe_prefix_payload(codec, packet.data)
          }

        codec ->
          AudioData.new(packet.data, codec, 3, 1, :stereo)
      end

    {dts, Serializer.serialize(tag) |> IO.iodata_to_binary()}
  end

  defp maybe_prefix_payload(codec, payload) when codec in [:h264, :h265] do
    Enum.map(payload, &[<<byte_size(&1)::32>>, &1])
  end

  defp maybe_prefix_payload(_codec, payload), do: payload
end
