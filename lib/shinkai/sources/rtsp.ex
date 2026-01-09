defmodule Shinkai.Sources.RTSP do
  @moduledoc false

  use GenServer

  require Logger

  import Shinkai.Utils

  alias MediaCodecs.MPEG4
  alias Shinkai.Track

  @timeout 6_000
  @reconnect_timeout 5_000

  @spec start_link(Shinkai.Sources.Source.t()) :: GenServer.on_start()
  def start_link(source) do
    GenServer.start_link(__MODULE__, source)
  end

  @impl true
  def init(source) do
    Logger.info("[#{source.id}] Starting new rtsp source")

    {:ok, pid} = RTSP.start_link(stream_uri: source.uri)

    if function_exported?(Process, :set_label, 1) do
      apply(Process, :set_label, [{:rtsp, source.id}])
    end

    state = %{
      id: source.id,
      rtsp_pid: pid,
      tracks: %{},
      packets_topic: packets_topic(source.id)
    }

    {:ok, state, {:continue, :connect}}
  end

  @impl true
  def handle_continue(:connect, state), do: do_connect(state)

  @impl true
  def handle_info(:reconnect, state), do: do_connect(state)

  def handle_info({:rtsp, _pid, {id, sample_or_samples}}, state) do
    :ok =
      Phoenix.PubSub.broadcast(
        Shinkai.PubSub,
        state.packets_topic,
        {:packet, to_packets(sample_or_samples, state.tracks[id].id)}
      )

    {:noreply, state}
  end

  @impl true
  def handle_info({:rtsp, pid, :session_closed}, %{rtsp_pid: pid} = state) do
    Logger.error("[#{state.id}] rtsp client disconnected")
    Phoenix.PubSub.broadcast!(Shinkai.PubSub, state_topic(state.id), :disconnected)
    Process.send_after(self(), :reconnect, @reconnect_timeout)
    {:noreply, state}
  end

  @impl true
  def handle_info(msg, state) do
    Logger.warning("[#{state.id}] unhandled message: #{inspect(msg)}")
    {:noreply, state}
  end

  defp do_connect(state) do
    with {:ok, tracks} <- RTSP.connect(state.rtsp_pid, @timeout),
         tracks <- build_tracks(tracks),
         :ok <- RTSP.play(state.rtsp_pid) do
      codecs = tracks |> Map.values() |> Enum.map_join(", ", & &1.codec)
      Logger.info("[#{state.id}] start reading from #{map_size(tracks)} tracks (#{codecs})")

      :ok =
        Phoenix.PubSub.broadcast(
          Shinkai.PubSub,
          tracks_topic(state.id),
          {:tracks, Map.values(tracks)}
        )

      {:noreply, %{state | tracks: tracks}}
    else
      {:error, reason} ->
        Logger.error("[#{state.id}] rtsp connection failed: #{inspect(reason)}")
        Process.send_after(self(), :reconnect, @reconnect_timeout)
        {:noreply, state}
    end
  end

  defp build_tracks(tracks) do
    tracks
    |> Enum.with_index(1)
    |> Map.new(fn {track, id} ->
      codec = codec(String.downcase(track.rtpmap.encoding))

      {track.control_path,
       Track.new(
         id: id,
         type: track.type,
         codec: codec,
         timescale: track.rtpmap.clock_rate,
         priv_data: priv_data(codec, track.fmtp)
       )}
    end)
  end

  defp codec("mpeg4-generic"), do: :aac
  defp codec(other), do: String.to_atom(other)

  defp priv_data(:aac, fmtp), do: MPEG4.AudioSpecificConfig.parse(fmtp.config)
  defp priv_data(_codec, _fmtp), do: nil

  defp to_packets(samples, track_id) when is_list(samples) do
    Enum.map(samples, &packet_from_sample(track_id, &1))
  end

  defp to_packets(sample, track_id), do: packet_from_sample(track_id, sample)

  defp packet_from_sample(track_id, {payload, pts, sync?, _timestamp}) do
    Shinkai.Packet.new(payload,
      track_id: track_id,
      dts: pts,
      pts: pts,
      sync?: sync?
    )
  end
end
