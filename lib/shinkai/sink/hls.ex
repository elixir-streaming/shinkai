defmodule Shinkai.Sink.Hls do
  @moduledoc """
  Module describing an HLS sink.
  """

  use GenServer

  import Shinkai.Utils

  alias HLX.Writer

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: opts[:name])
  end

  @impl true
  def init(opts) do
    {id, config} = Keyword.pop!(opts, :id)

    hls_config = [
      type: :master,
      storage_dir: Path.join(config[:storage_dir], id),
      segment_duration: config[:segment_duration],
      part_duration: config[:part_duration],
      max_segments: config[:max_segments],
      segment_type: config[:segment_type]
    ]

    File.rm_rf!(hls_config[:storage_dir])

    :ok = Phoenix.PubSub.subscribe(Shinkai.PubSub, tracks_topic(id))
    :ok = Phoenix.PubSub.subscribe(Shinkai.PubSub, state_topic(id))

    {:ok,
     %{
       writer: Writer.new!(hls_config),
       config: hls_config,
       source_id: id,
       tracks: %{},
       last_sample: %{}
     }}
  end

  @impl true
  def handle_info({:tracks, tracks}, state) do
    hls_tracks =
      Enum.map(tracks, fn track ->
        HLX.Track.new(
          id: track.id,
          type: track.type,
          codec: track.codec,
          priv_data: track.priv_data,
          timescale: track.timescale
        )
      end)

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

    Phoenix.PubSub.subscribe(Shinkai.PubSub, packets_topic(state.source_id))
    {:noreply, %{state | writer: writer, tracks: Map.new(tracks, fn t -> {t.id, t} end)}}
  end

  @impl true
  def handle_info({:packet, packet}, state) do
    case Map.fetch(state.last_sample, packet.track_id) do
      :error ->
        last_samples = Map.put(state.last_sample, packet.track_id, packet_to_sample(packet))
        {:noreply, %{state | last_sample: last_samples}}

      {:ok, last_sample} ->
        variant_name = state.tracks[packet.track_id].type |> to_string()
        sample = packet_to_sample(packet)
        last_sample = %{last_sample | duration: sample.dts - last_sample.dts}

        {:noreply,
         %{
           state
           | writer: Writer.write_sample(state.writer, variant_name, last_sample),
             last_sample: Map.put(state.last_sample, packet.track_id, sample)
         }}
    end
  end

  @impl true
  def handle_info(:disconnected, state) do
    :ok = Writer.close(state.writer)
    :ok = Phoenix.PubSub.unsubscribe(Shinkai.PubSub, packets_topic(state.source_id))
    {:noreply, %{state | writer: Writer.new!(state.config), last_sample: %{}}}
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
