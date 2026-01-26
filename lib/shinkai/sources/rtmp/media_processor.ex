defmodule Shinkai.Sources.RTMP.MediaProcessor do
  @moduledoc false

  import Shinkai.Utils

  require Logger

  alias Phoenix.PubSub
  alias Shinkai.{Packet, Track}

  @max_buffer 100
  @timescale 1000

  @type state :: %{
          source_id: String.t(),
          app: String.t() | nil,
          audio_track: Track.t() | nil,
          video_track: Track.t() | nil,
          buffer?: boolean(),
          buffer_len: non_neg_integer(),
          packets: [Packet.t()],
          packets_topic: String.t()
        }

  @spec new(String.t()) :: state()
  def new(source_id) do
    %{
      source_id: source_id,
      audio_track: nil,
      video_track: nil,
      buffer?: true,
      buffer_len: 0,
      packets: [],
      packets_topic: packets_topic(source_id)
    }
  end

  @spec handle_video_data(tuple(), state()) :: state()
  def handle_video_data({:codec, codec, init_data}, state) do
    track =
      Track.new(
        id: 1,
        type: :video,
        codec: codec,
        timescale: 90_000,
        priv_data: track_priv_data(codec, init_data)
      )

    state = %{state | video_track: track}
    if state.audio_track, do: unbuffer(state), else: state
  end

  def handle_video_data(sample, %{buffer?: false} = state) do
    packet = packet_from_sample(state.video_track, sample)
    PubSub.broadcast(Shinkai.PubSub, state.packets_topic, {:packet, packet})
    state
  end

  def handle_video_data(sample, %{buffer_len: len} = state) when len >= @max_buffer do
    handle_video_data(sample, unbuffer(state))
  end

  def handle_video_data(sample, state) do
    %{
      state
      | packets: [packet_from_sample(state.video_track, sample) | state.packets],
        buffer_len: state.buffer_len + 1
    }
  end

  @spec handle_audio_data(tuple(), state()) :: state()
  def handle_audio_data({:codec, codec, init_data}, state) do
    track =
      Track.new(
        id: 2,
        type: :audio,
        codec: codec,
        timescale: @timescale,
        priv_data: track_priv_data(codec, init_data)
      )

    track =
      case track.codec do
        :aac -> %{track | timescale: track.priv_data.sampling_frequency}
        :opus -> %{track | timescale: 48_000}
        _codec -> track
      end

    state = %{state | audio_track: track}
    if state.video_track, do: unbuffer(state), else: state
  end

  def handle_audio_data(sample, %{buffer?: false} = state) do
    PubSub.broadcast(
      Shinkai.PubSub,
      state.packets_topic,
      {:packet, packet_from_sample(state.audio_track, sample)}
    )

    state
  end

  def handle_audio_data(sample, %{buffer_len: len} = state) when len >= @max_buffer do
    handle_audio_data(sample, unbuffer(state))
  end

  def handle_audio_data(sample, state) do
    %{
      state
      | packets: [packet_from_sample(state.audio_track, sample) | state.packets],
        buffer_len: state.buffer_len + 1
    }
  end

  defp unbuffer(state) do
    tracks = [state.video_track, state.audio_track]

    Logger.info(
      "[#{state.source_id}] reading #{length(tracks)} track(s) (#{Enum.map_join(tracks, ", ", & &1.codec)})"
    )

    [state.video_track, state.audio_track]
    |> Enum.reject(&is_nil/1)
    |> then(&PubSub.broadcast(Shinkai.PubSub, tracks_topic(state.source_id), {:tracks, &1}))

    state.packets
    |> Enum.reverse()
    |> Enum.each(&PubSub.broadcast(Shinkai.PubSub, state.packets_topic, {:packet, &1}))

    %{state | buffer?: false, packets: [], buffer_len: 0}
  end

  defp track_priv_data(:h264, init_data) do
    avcc = ExMP4.Box.parse(%ExMP4.Box.Avcc{}, init_data)
    {List.first(avcc.sps), avcc.pps}
  end

  defp track_priv_data(:h265, init_data) do
    hvcc = ExMP4.Box.parse(%ExMP4.Box.Hvcc{}, init_data)
    {List.first(hvcc.vps), List.first(hvcc.sps), hvcc.pps}
  end

  defp track_priv_data(:av1, init_data) do
    av1c = ExMP4.Box.parse(%ExMP4.Box.Av1c{}, init_data)

    if av1c.config_obus != <<>>, do: av1c.config_obus
  end

  defp track_priv_data(:aac, init_data) do
    MediaCodecs.MPEG4.AudioSpecificConfig.parse(init_data)
  end

  defp track_priv_data(:opus, _init_data), do: nil

  defp track_priv_data(_codec, init_data), do: init_data

  @compile {:inline, packet_from_sample: 2}
  defp packet_from_sample(track, {:sample, payload, dts, pts, sync?}) do
    %Packet{
      track_id: track.id,
      data: payload,
      dts: div(dts * track.timescale, @timescale),
      pts: div(pts * track.timescale, @timescale),
      sync?: sync?
    }
  end

  defp packet_from_sample(track, {:sample, payload, pts}) do
    pts = div(pts * track.timescale, @timescale)

    %Packet{
      track_id: track.id,
      data: payload,
      dts: pts,
      pts: pts,
      sync?: true
    }
  end
end
