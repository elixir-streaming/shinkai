defmodule Shinkai.Sink.RTMP do
  @moduledoc """
  Module describing an RTMP sink.

  The module is responsible for converting received packets into FLV tags and forward them to clients.
  """

  use GenServer

  require Logger

  import Shinkai.Utils

  alias ExFLV.Tag.{Serializer, VideoData}
  alias Phoenix.PubSub

  @timescale 1000

  def start_link(opts) do
    name = {:via, Registry, {Source.Registry, :rtmp_sink, opts[:id]}}
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
        :video -> ExRTMP.Server.ClientSession.send_video_data(pid, 0, tag)
        :audio -> ExRTMP.Server.ClientSession.send_audio_data(pid, 0, tag)
      end
    end

    {:reply, :ok, state}
  end

  @impl true
  def handle_info({:tracks, tracks}, state) do
    init_tags =
      Map.new(tracks, fn track ->
        tag =
          track
          |> Shinkai.Track.to_rtmp_tag()
          |> ExFLV.Tag.Serializer.serialize()

        {track.id, tag}
      end)

    :ok = PubSub.subscribe(Shinkai.PubSub, state.packet_topic)
    {:noreply, %{state | tracks: Map.new(tracks, &{&1.id, &1}), init_tags: init_tags}}
  end

  @impl true
  def handle_info({:packet, packets}, state) do
    Registry.dispatch(Sink.Registry, {:rtmp, state.source_id}, fn entries ->
      packets = List.wrap(packets)
      track = state.tracks[hd(packets).track_id]
      tags = Enum.map(packets, &packet_to_tag(track, &1))

      for {pid, _} <- entries, {timestamp, data} <- tags do
        case track.type do
          :video -> ExRTMP.Server.ClientSession.send_video_data(pid, timestamp, data)
          :audio -> ExRTMP.Server.ClientSession.send_audio_data(pid, timestamp, data)
        end
      end
    end)

    {:noreply, state}
  end

  defp packet_to_tag(track, packet) do
    dts = div(packet.dts * @timescale, track.timescale)
    cts = div((packet.pts - packet.dts) * @timescale, track.timescale)

    tag =
      case track.codec do
        :h264 ->
          packet.data
          |> Enum.map(&[<<byte_size(&1)::32>>, &1])
          |> VideoData.AVC.new(:nalu, cts)
          |> VideoData.new(:h264, if(packet.sync?, do: :keyframe, else: :interframe))
          |> Serializer.serialize()
      end

    {dts, IO.iodata_to_binary(tag)}
  end
end
