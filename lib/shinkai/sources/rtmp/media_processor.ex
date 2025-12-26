defmodule Shinkai.Sources.RTMP.MediaProcessor do
  @moduledoc false

  import Shinkai.Utils

  require Logger

  alias Phoenix.PubSub
  alias Shinkai.{Packet, Track}

  @max_buffer 100

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
    track = Track.new(id: 1, type: :video, codec: codec, timescale: 1000)

    track =
      if codec == :avc do
        avcc = ExMP4.Box.parse(%ExMP4.Box.Avcc{}, init_data)
        %{track | codec: :h264, priv_data: {List.first(avcc.sps), avcc.pps}}
      else
        track
      end

    state = %{state | video_track: track}
    if state.audio_track, do: unbuffer(state), else: state
  end

  def handle_video_data(sample, %{buffer?: false} = state) do
    packet = packet_from_sample(state.video_track.id, sample)
    PubSub.broadcast(Shinkai.PubSub, state.packets_topic, {:packet, packet})
    state
  end

  def handle_video_data(sample, %{buffer_len: len} = state) when len >= @max_buffer do
    handle_video_data(sample, unbuffer(state))
  end

  def handle_video_data(sample, state) do
    %{
      state
      | packets: [packet_from_sample(state.video_track.id, sample) | state.packets],
        buffer_len: state.buffer_len + 1
    }
  end

  @spec handle_audio_data(tuple(), state()) :: state()
  def handle_audio_data({:codec, codec, init_data}, state) do
    track = Track.new(id: 2, type: :audio, codec: codec, timescale: 1000)

    track = if codec == :aac, do: %{track | priv_data: init_data}, else: track

    state = %{state | audio_track: track}
    if state.video_track, do: unbuffer(state), else: state
  end

  def handle_audio_data(sample, %{buffer?: false} = state) do
    PubSub.broadcast(
      Shinkai.PubSub,
      state.packets_topic,
      {:packet, packet_from_sample(state.audio_track.id, sample)}
    )

    state
  end

  def handle_audio_data(sample, %{buffer_len: len} = state) when len >= @max_buffer do
    handle_audio_data(sample, unbuffer(state))
  end

  def handle_audio_data(sample, state) do
    %{
      state
      | packets: [packet_from_sample(state.audio_track.id, sample) | state.packets],
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

  @compile {:inline, packet_from_sample: 2}
  defp packet_from_sample(track_id, {:sample, payload, dts, pts, sync?}) do
    %Packet{
      track_id: track_id,
      data: payload,
      dts: dts,
      pts: pts,
      sync?: sync?
    }
  end

  defp packet_from_sample(track_id, {:sample, payload, pts}) do
    %Packet{
      track_id: track_id,
      data: payload,
      dts: pts,
      pts: pts,
      sync?: true
    }
  end
end
