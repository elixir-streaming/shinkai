defmodule Shinkai.Sources.RTSP.MediaProcessor do
  @moduledoc false

  require Logger

  alias MediaCodecs.AV1
  alias Shinkai.{Sources, Track}

  @max_buffer 1000

  @type t :: %{
          source_id: Sources.Source.id(),
          tracks: %{String.t() => Track.t()},
          buffer?: boolean(),
          packets: [Shinkai.Packet.t()],
          buffered_packets: non_neg_integer()
        }

  @spec new(Sources.Source.id(), [map()]) :: t()
  def new(source_id, tracks) do
    tracks =
      tracks
      |> Enum.with_index(1)
      |> Map.new(fn {track, id} -> {track.control_path, Track.from_rtsp_track(id, track)} end)

    ready? = all_tracks_initialized?(Map.values(tracks))

    Logger.info(
      "[#{source_id}] reading #{map_size(tracks)} track(s) (#{Enum.map_join(Map.values(tracks), ", ", & &1.codec)})"
    )

    if ready? do
      Phoenix.PubSub.broadcast!(
        Shinkai.PubSub,
        Shinkai.Utils.tracks_topic(source_id),
        {:tracks, Map.values(tracks)}
      )
    end

    %{
      source_id: source_id,
      tracks: tracks,
      buffer?: not ready?,
      packets: [],
      packets_topic: Shinkai.Utils.packets_topic(source_id),
      buffered_packets: 0
    }
  end

  @spec handle_sample(String.t(), tuple(), t()) :: t()
  def handle_sample(id, sample, %{buffer?: false} = state) do
    track = state.tracks[id]
    packet = to_packet(track, sample)
    Phoenix.PubSub.broadcast!(Shinkai.PubSub, state.packets_topic, {:packet, packet})
    state
  end

  def handle_sample(id, sample, state) do
    track = state.tracks[id]

    case maybe_init_track(track, sample) do
      {:ok, updated_track} ->
        tracks = Map.put(state.tracks, id, updated_track)

        state = %{
          state
          | tracks: tracks,
            packets: [to_packet(updated_track, sample) | state.packets],
            buffered_packets: state.buffered_packets + 1
        }

        cond do
          all_tracks_initialized?(Map.values(tracks)) -> unbuffer(state)
          state.buffered_packets > @max_buffer -> %{state | packets: [], buffered_packets: 0}
          true -> state
        end

      :discard ->
        state
    end
  end

  defp all_tracks_initialized?(tracks) do
    Enum.all?(tracks, fn
      %{type: :video, priv_data: nil} -> false
      _track -> true
    end)
  end

  defp maybe_init_track(%{type: :video, priv_data: nil}, {_payload, _pts, false, _timestamp}) do
    :discard
  end

  defp maybe_init_track(
         %{type: :video, priv_data: nil} = track,
         {payload, _pts, true, _timestamp}
       ) do
    with {:ok, priv_data} <- look_for_parameter_sets(track.codec, payload) do
      {:ok, %{track | priv_data: priv_data}}
    end
  end

  defp maybe_init_track(track, _sample), do: {:ok, track}

  defp look_for_parameter_sets(:h264, payload) do
    {{sps, pps}, _rest} = MediaCodecs.H264.pop_parameter_sets(payload)
    if sps != [] and pps != [], do: {:ok, {List.first(sps), pps}}, else: :discard
  end

  defp look_for_parameter_sets(:h265, payload) do
    {{vps, sps, pps}, _rest} = MediaCodecs.H265.pop_parameter_sets(payload)

    if vps != [] and sps != [] and pps != [],
      do: {:ok, {List.first(vps), List.first(sps), pps}},
      else: :discard
  end

  defp look_for_parameter_sets(:av1, payload) do
    case Enum.find(payload, &(AV1.OBU.type(&1) == :sequence_header)) do
      nil -> :discard
      seq_header_obu -> {:ok, seq_header_obu}
    end
  end

  defp unbuffer(state) do
    Phoenix.PubSub.broadcast!(
      Shinkai.PubSub,
      Shinkai.Utils.tracks_topic(state.source_id),
      {:tracks, Map.values(state.tracks)}
    )

    state.packets
    |> Enum.reverse()
    |> List.flatten()
    |> Enum.each(&Phoenix.PubSub.broadcast!(Shinkai.PubSub, state.packets_topic, {:packet, &1}))

    %{state | buffer?: false, packets: []}
  end

  defp to_packet(track, {payload, pts, sync?, _timestamp}) do
    payload =
      case track.codec do
        :av1 -> Enum.map(payload, &AV1.OBU.set_size_flag/1)
        _ -> payload
      end

    Shinkai.Packet.new(payload,
      track_id: track.id,
      dts: pts,
      pts: pts,
      sync?: sync?
    )
  end

  defp to_packet(track, samples), do: Enum.map(samples, &to_packet(track, &1))
end
