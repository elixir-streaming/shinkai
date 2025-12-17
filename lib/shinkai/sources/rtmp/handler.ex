defmodule Shinkai.Sources.RTMP.Handler do
  @moduledoc false

  use ExRTMP.Server.Handler

  import Shinkai.Utils

  alias Phoenix.PubSub
  alias Shinkai.{Packet, Track}

  @max_buffer 100

  @impl true
  def init(_args) do
    %{
      source_id: nil,
      app: nil,
      audio_track: nil,
      video_track: nil,
      buffer?: true,
      packets: [],
      packets_topic: nil
    }
  end

  @impl true
  def handle_connect(connect, state) do
    {:ok, %{state | app: connect.properties["app"]}}
  end

  @impl true
  def handle_play(_play, _state) do
    {:error, :unsupported}
  end

  @impl true
  def handle_publish(stream_key, state) do
    source_id = "#{state.app}-#{stream_key}"
    source = %Shinkai.Sources.Source{id: source_id, type: :rtmp, uri: :publish}

    {:ok, _pid} = Shinkai.Sources.start(source)

    {:ok, %{state | source_id: source_id, packets_topic: packets_topic(source_id)}}
  end

  @impl true
  def handle_video_data(_timestamp, {:codec, codec, init_data}, state) do
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

  def handle_video_data(_timestamp, sample, %{buffer?: false} = state) do
    PubSub.broadcast(
      Shinkai.PubSub,
      packets_topic(state.source_id),
      {:packet, packet_from_sample(state.video_track.id, sample)}
    )

    state
  end

  def handle_video_data(timestamp, sample, state) when length(state.packets) >= @max_buffer do
    handle_video_data(timestamp, sample, unbuffer(state))
  end

  def handle_video_data(_timestamp, sample, state) do
    %{state | packets: [packet_from_sample(state.video_track.id, sample) | state.packets]}
  end

  @impl true
  def handle_audio_data(_timestamp, {:codec, codec, init_data}, state) do
    track = Track.new(id: 2, type: :audio, codec: codec, timescale: 1000)

    track = if codec == :aac, do: %{track | priv_data: init_data}, else: track

    state = %{state | audio_track: track}
    if state.video_track, do: unbuffer(state), else: state
  end

  @impl true
  def handle_audio_data(_timestamp, sample, %{buffer?: false} = state) do
    PubSub.broadcast(
      Shinkai.PubSub,
      packets_topic(state.source_id),
      {:packet, packet_from_sample(state.audio_track.id, sample)}
    )

    state
  end

  def handle_audio_data(timestamp, sample, state) when length(state.packets) >= @max_buffer do
    handle_video_data(timestamp, sample, unbuffer(state))
  end

  def handle_audio_data(_timestamp, sample, state) do
    %{state | packets: [packet_from_sample(state.audio_track.id, sample) | state.packets]}
  end

  defp unbuffer(state) do
    [state.video_track, state.audio_track]
    |> Enum.reject(&is_nil/1)
    |> then(&PubSub.broadcast(Shinkai.PubSub, tracks_topic(state.source_id), {:tracks, &1}))

    state.packets
    |> Enum.reverse()
    |> Enum.each(&PubSub.broadcast(Shinkai.PubSub, state.packets_topic, {:packet, &1}))

    %{state | buffer?: false, packets: []}
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
