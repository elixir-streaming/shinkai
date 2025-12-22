defmodule Shinkai.Sink.Hls do
  @moduledoc """
  Module describing an HLS sink.
  """

  use GenServer

  require Logger

  import Shinkai.Utils

  alias __MODULE__.RequestHolder
  alias HLX.Writer
  alias Phoenix.PubSub

  @supported_codecs [:h264, :h265, :av1, :aac]

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: opts[:name])
  end

  @impl true
  def init(opts) do
    {id, hls_config} = Keyword.pop!(opts, :id)
    {dir, hls_config} = Keyword.pop(hls_config, :storage_dir)
    hls_config = [type: :master, storage_dir: Path.join(dir, id)] ++ hls_config

    hls_config =
      if hls_config[:segment_type] == :low_latency do
        on_part_created = fn variant_id, part ->
          send(
            :"request_holder_#{id}",
            {:hls_part, variant_id, part.segment_index, part.index}
          )
        end

        hls_config ++ [on_part_created: on_part_created]
      else
        hls_config
      end

    File.rm_rf!(hls_config[:storage_dir])

    :ok = Phoenix.PubSub.subscribe(Shinkai.PubSub, tracks_topic(id))
    :ok = Phoenix.PubSub.subscribe(Shinkai.PubSub, state_topic(id))

    {:ok, _} = RequestHolder.start_link(:"request_holder_#{id}")

    {:ok,
     %{
       writer: Writer.new!(hls_config),
       config: hls_config,
       source_id: id,
       tracks: %{},
       last_sample: %{},
       buffer?: false,
       packets: []
     }}
  end

  @impl true
  def handle_info({:tracks, tracks}, state) do
    hls_tracks = Enum.map(tracks, &Shinkai.Track.to_hls_track/1)

    {hls_tracks, unsupported_tracks} =
      Enum.split_with(hls_tracks, fn t -> t.codec in @supported_codecs end)

    if unsupported_tracks != [] do
      Logger.warning(
        "[#{state.source_id}] mux hls: ignore unsupported codecs: #{Enum.map_join(unsupported_tracks, ", ", & &1.codec)}"
      )
    end

    audio_track = Enum.find(hls_tracks, fn t -> t.type == :audio end)
    video_track = Enum.find(hls_tracks, fn t -> t.type == :video end)

    writer =
      cond do
        not is_nil(audio_track) and not is_nil(video_track) ->
          state.writer
          |> Writer.add_rendition!("audio", track: audio_track, group_id: "audio")
          |> Writer.add_variant!("video", tracks: [video_track], audio: "audio")

        not is_nil(audio_track) ->
          Writer.add_variant!(state.writer, "audio", tracks: [audio_track])

        true ->
          Writer.add_variant!(state.writer, "video", tracks: [video_track])
      end

    buffer? = length(hls_tracks) > 1 and Enum.any?(hls_tracks, &(&1.type == :video))
    :ok = PubSub.subscribe(Shinkai.PubSub, packets_topic(state.source_id))

    {:noreply,
     %{
       state
       | writer: writer,
         tracks: Map.new(hls_tracks, fn t -> {t.id, t} end),
         buffer?: buffer?
     }}
  end

  def handle_info({:packet, packets}, state) when is_list(packets) do
    {:noreply, Enum.reduce(packets, state, &do_handle_packet/2)}
  end

  @impl true
  def handle_info({:packet, packet}, state) do
    {:noreply, do_handle_packet(packet, state)}
  end

  @impl true
  def handle_info(:disconnected, state) do
    :ok = Writer.close(state.writer)
    :ok = PubSub.unsubscribe(Shinkai.PubSub, packets_topic(state.source_id))
    :ok = PubSub.local_broadcast(Shinkai.PubSub, sink_topic(state.source_id), {:hls, :done})

    {:noreply,
     %{state | writer: Writer.new!(state.config), last_sample: %{}, packets: [], buffer?: false}}
  end

  defp do_handle_packet(%{track_id: id}, state) when not is_map_key(state.tracks, id) do
    state
  end

  defp do_handle_packet(packet, %{buffer?: true} = state) do
    # buffer until we get a video packet
    # and then drop all packets with dts < dts of that video packet
    track = state.tracks[packet.track_id]

    if track.type == :video do
      packets = [packet | state.packets]
      max_dts = ExMP4.Helper.timescalify(packet.dts, track.timescale, :millisecond)
      state = %{state | packets: [], buffer?: false}

      packets
      |> Enum.reverse()
      |> List.flatten()
      |> Enum.reject(&reject?(&1, state, max_dts))
      |> Enum.reduce(state, &do_handle_packet/2)
    else
      %{state | packets: [packet | state.packets]}
    end
  end

  defp do_handle_packet(packet, state) do
    case Map.fetch(state.last_sample, packet.track_id) do
      :error ->
        last_samples = Map.put(state.last_sample, packet.track_id, packet_to_sample(packet))
        %{state | last_sample: last_samples}

      {:ok, last_sample} ->
        variant_name = state.tracks[packet.track_id].type |> to_string()
        sample = packet_to_sample(packet)
        last_sample = %{last_sample | duration: sample.dts - last_sample.dts}

        %{
          state
          | writer: Writer.write_sample(state.writer, variant_name, last_sample),
            last_sample: Map.put(state.last_sample, packet.track_id, sample)
        }
    end
  end

  defp reject?(packet, state, max_dts) do
    track = state.tracks[packet.track_id]
    packet_dts = ExMP4.Helper.timescalify(packet.dts, track.timescale, :millisecond)
    packet_dts < max_dts
  end

  defp packet_to_sample(packet) do
    %HLX.Sample{
      track_id: packet.track_id,
      dts: packet.dts,
      pts: packet.pts,
      payload: packet.data,
      sync?: packet.sync?
    }
  end
end
