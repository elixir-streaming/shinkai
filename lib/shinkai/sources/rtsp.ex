defmodule Shinkai.Sources.RTSP do
  @moduledoc false

  use GenServer

  require Logger

  import Shinkai.Utils

  alias Shinkai.Track

  @timeout 6_000

  def start_link(source) do
    GenServer.start_link(__MODULE__, source)
  end

  @impl true
  def init(source) do
    Logger.info("[#{source.id}] Starting new rtsp source")

    {:ok, pid} = RTSP.start_link(stream_uri: source.uri)
    Process.set_label({:rtsp, source.id})

    state = %{
      id: source.id,
      rtsp_pid: pid,
      tracks: %{},
      packets_topic: packets_topic(source.id)
    }

    {:ok, state, {:continue, :connect}}
  end

  @impl true
  def handle_continue(:connect, state) do
    {:ok, tracks} = RTSP.connect(state.rtsp_pid, @timeout)

    tracks =
      tracks
      |> Enum.with_index(1)
      |> Map.new(fn {track, id} ->
        {track.control_path,
         Track.new(
           id: id,
           type: track.type,
           codec: track.rtpmap.encoding |> String.downcase() |> String.to_atom(),
           timescale: track.rtpmap.clock_rate
         )}
      end)

    :ok =
      Phoenix.PubSub.broadcast(
        Shinkai.PubSub,
        tracks_topic(state.id),
        {:tracks, Map.values(tracks)}
      )

    :ok = RTSP.play(state.rtsp_pid, @timeout)
    {:noreply, %{state | tracks: tracks}}
  end

  @impl true
  def handle_info(
        {:rtsp, _pid, {id, {sample, rtp_timestamp, keyframe?, _timestamp}}},
        state
      ) do
    packet =
      Shinkai.Packet.new(sample,
        track_id: state.tracks[id].id,
        dts: rtp_timestamp,
        pts: rtp_timestamp,
        sync?: keyframe?
      )

    :ok = Phoenix.PubSub.broadcast(Shinkai.PubSub, state.packets_topic, {:packet, packet})

    {:noreply, state}
  end

  @impl true
  def handle_info({:rtsp, pid, :session_closed}, %{rtsp_pid: pid} = state) do
    Logger.error("[#{state.id}] rtsp client disconnected")
    # implement retry logic here
    {:noreply, state}
  end
end
